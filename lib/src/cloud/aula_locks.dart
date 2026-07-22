// Travas de aula do workspace (/school/aulas/{deviceId}): garante que um PC
// só participa de UMA aula por vez, entre celulares de professores
// diferentes. Trava = {uid, ts, env}; env = {professor, turma} cifrado com a
// chave da escola (nome de turma não vaza em claro). Heartbeat renova o ts;
// trava sem heartbeat há >15 min é órfã (app morto) — o takeover é validado
// também nas rules (server-side).

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../secure/crypto.dart';

/// Trava órfã depois disso sem heartbeat (espelhado nas rules: 900000 ms).
const Duration kTravaExpira = Duration(minutes: 15);

/// Decisão pura de expiração (testável).
bool travaExpirada({required int ts, required int agoraMs}) =>
    agoraMs - ts > kTravaExpira.inMilliseconds;

class TravaDeAula {
  const TravaDeAula({required this.uid, required this.ts, this.professor, this.turma});

  final String uid;
  final int ts;
  final String? professor; // decifrado lazy; null = env ilegível/ausente
  final String? turma;
}

class AulaLocks {
  AulaLocks({
    required this.meuUid,
    required this.crypto,
    required this.nowServerMs,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final String meuUid;
  final SessionCrypto crypto;
  final int Function() nowServerMs;
  final FirebaseDatabase _db;

  final Map<String, TravaDeAula> _travas = {};
  StreamSubscription<DatabaseEvent>? _sub;

  /// Notifica mudanças (o controller repassa ao notifyListeners).
  VoidCallback? onChange;

  void start() {
    _sub = _db.ref('school/aulas').onValue.listen((e) async {
      final v = e.snapshot.value;
      final novo = <String, TravaDeAula>{};
      if (v is Map) {
        for (final entry in v.entries) {
          final t = entry.value;
          if (t is! Map) continue;
          final uid = t['uid'], ts = t['ts'];
          if (uid is! String || ts is! num) continue;
          String? professor;
          String? turma;
          final env = t['env'];
          if (env is String) {
            try {
              final msg = await crypto.open(env);
              professor = msg['professor'] as String?;
              turma = msg['turma'] as String?;
            } catch (_) {
              // chave antiga/ilegível — trava vale mesmo sem os nomes
            }
          }
          novo['${entry.key}'] = TravaDeAula(
            uid: uid,
            ts: ts.toInt(),
            professor: professor,
            turma: turma,
          );
        }
      }
      _travas
        ..clear()
        ..addAll(novo);
      onChange?.call();
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  TravaDeAula? travaDe(String deviceId) => _travas[deviceId];

  /// PC preso na aula de OUTRO professor (trava viva)?
  bool travadoPorOutro(String deviceId) {
    final t = _travas[deviceId];
    if (t == null || t.uid == meuUid) return false;
    return !travaExpirada(ts: t.ts, agoraMs: nowServerMs());
  }

  /// Mensagem "Em aula com {prof} ({turma})" para a UI, se preso.
  String? motivoDe(String deviceId) {
    final t = _travas[deviceId];
    if (t == null) return null;
    final quem = t.professor ?? 'outro professor';
    return t.turma != null ? 'Em aula com $quem (${t.turma})' : 'Em aula com $quem';
  }

  /// Trava o PC para a MINHA aula. Retorna null (ok) ou o motivo da recusa.
  /// As rules garantem o lado servidor; a transação evita corrida local.
  Future<String?> travar(String deviceId, {required String professor, required String turma}) async {
    final env = await crypto.seal({'professor': professor, 'turma': turma});
    try {
      final agora = nowServerMs();
      final result = await _db.ref('school/aulas/$deviceId').runTransaction((atual) {
        if (atual is Map) {
          final uid = atual['uid'], ts = atual['ts'];
          final viva = uid is String &&
              uid != meuUid &&
              ts is num &&
              !travaExpirada(ts: ts.toInt(), agoraMs: agora);
          if (viva) return Transaction.abort();
        }
        return Transaction.success({'uid': meuUid, 'ts': agora, 'env': env});
      });
      if (!result.committed) {
        return motivoDe(deviceId) ?? 'Este PC está na aula de outro professor.';
      }
      return null;
    } catch (e) {
      debugPrint('[CdA] travar $deviceId falhou: $e');
      return 'Não deu para reservar o PC — verifique a internet.';
    }
  }

  Future<void> destravar(String deviceId) async {
    final t = _travas[deviceId];
    if (t != null && t.uid != meuUid) return; // não é minha
    await _db.ref('school/aulas/$deviceId').remove().catchError((_) {});
  }

  /// Remove todas as MINHAS travas (encerrar aula).
  Future<void> destravarTodas() async {
    for (final e in _travas.entries.toList()) {
      if (e.value.uid == meuUid) {
        await _db.ref('school/aulas/${e.key}').remove().catchError((_) {});
      }
    }
  }

  /// Renova o ts das minhas travas (chamar num Timer com a aula ativa).
  Future<void> heartbeat() async {
    final agora = nowServerMs();
    for (final e in _travas.entries.toList()) {
      if (e.value.uid == meuUid) {
        await _db
            .ref('school/aulas/${e.key}/ts')
            .set(agora)
            .catchError((_) {});
      }
    }
  }
}
