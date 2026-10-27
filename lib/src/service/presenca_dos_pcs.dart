// Quantos PCs estão ligados, para a notificação fixa do serviço em primeiro
// plano (isolate próprio, vivo com o app fechado). Lê o roster e o
// presence/lastSeen de cada PC, os mesmos caminhos do transporte (o SDK junta
// os listens iguais). Sem chave de cifra: só presença.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../cloud/server_clock.dart';
import '../cloud/session_registry.dart';

/// PCs com presença na janela de online, a mesma regra de
/// [PcSession.online]. [agoraMs] e os lastSeen no relógio do servidor.
int contarOnline(Iterable<int?> lastSeen, int agoraMs) => lastSeen
    .where((ms) => ms != null && agoraMs - ms < kJanelaOnline.inMilliseconds)
    .length;

String textoDaBarra(int online) => '$online PC(s) conectados';

/// Texto novo da notificação fixa só quando o número muda: cada
/// updateService reposta a notificação.
class TextoDaBarra {
  int? _ultimo;

  /// Texto ao subir o serviço; null = deixa o que está. Subindo pelo sistema
  /// (boot, atualização, Android), a notificação volta com o texto salvo da
  /// última contagem, talvez de ontem: fica 0 até contar de novo.
  String? aoSubir({required bool peloSistema}) {
    if (!peloSistema) return null;
    _ultimo = 0;
    return textoDaBarra(0);
  }

  /// null = nada a mudar (mesmo número, ou contagem ainda a caminho).
  String? aoContar(int? online) {
    if (online == null || online == _ultimo) return null;
    _ultimo = online;
    return textoDaBarra(online);
  }
}

class PresencaDosPcs {
  PresencaDosPcs({required this.rosterPath, FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  /// school/devices na escola; teachers/{uid}/devices fora dela.
  final String rosterPath;
  final FirebaseDatabase _db;
  final RelogioDoServidor relogio = RelogioDoServidor();

  /// O SDK está falando com o servidor (.info/connected)?
  bool conectado = false;

  /// Presença ou roster mudou.
  VoidCallback? onChange;

  final List<StreamSubscription<DatabaseEvent>> _gerais = [];
  final Map<String, StreamSubscription<DatabaseEvent>> _porPc = {};
  final Map<String, int?> _lastSeen = {};
  final Set<String> _aCaminho = {};
  bool _rosterRecebido = false;

  void iniciar() {
    _gerais.addAll([
      _db
          .ref('.info/serverTimeOffset')
          .onValue
          .listen((e) => relogio.aoReceberOffset(e.snapshot.value)),
      _db.ref('.info/connected').onValue.listen((e) {
        conectado = e.snapshot.value == true;
        relogio.aoMudarConexao(e.snapshot.value);
      }),
      _db.ref(rosterPath).onValue.listen(
        (e) {
          final v = e.snapshot.value;
          _aplicarRoster(v is Map ? v.keys.map((k) => '$k') : const []);
        },
        // Fora da escola (e-mail tirado da lista): nenhum PC para contar.
        onError: (Object e) {
          debugPrint('[CdA] serviço: roster: $e');
          _aplicarRoster(const []);
        },
      ),
    ]);
  }

  /// PCs ligados agora; null = roster ou presença de algum PC ainda a
  /// caminho (não mostra um número que muda logo em seguida).
  int? online() {
    if (!_rosterRecebido || _aCaminho.isNotEmpty) return null;
    return contarOnline(_lastSeen.values, relogio.agora().millisecondsSinceEpoch);
  }

  Future<void> parar() async {
    final subs = [..._gerais, ..._porPc.values];
    _gerais.clear();
    _porPc.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  void _aplicarRoster(Iterable<String> ids) {
    final atuais = ids.toSet();
    for (final id in _porPc.keys.where((id) => !atuais.contains(id)).toList()) {
      unawaited(_porPc.remove(id)!.cancel());
      _lastSeen.remove(id);
      _aCaminho.remove(id);
    }
    for (final id in atuais.where((id) => !_porPc.containsKey(id))) {
      _aCaminho.add(id);
      _porPc[id] = _db.ref('devices/$id/presence/lastSeen').onValue.listen(
        (e) {
          final ms = e.snapshot.value;
          _lastSeen[id] = ms is num ? ms.toInt() : null;
          _aCaminho.remove(id);
          onChange?.call();
        },
        onError: (Object e) {
          debugPrint('[CdA] serviço: presença de $id: $e');
          _lastSeen[id] = null;
          _aCaminho.remove(id);
          onChange?.call();
        },
      );
    }
    _rosterRecebido = true;
    onChange?.call();
  }
}
