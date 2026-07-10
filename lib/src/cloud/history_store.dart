// Histórico de aulas por aluno, persistido no RTDB em envelopes cifrados
// (chave derivada da keypair do professor — ver history_crypto.dart).
// Layout: /history/{uid}/{sessionId}/{meta, ev/{pushId}} — ver protocolo.md.
// Retenção: para sempre; apagar manual pela UI.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../commands/command.dart';
import '../secure/crypto.dart';

/// Meta decifrada de uma sessão de aula.
class AulaMeta {
  AulaMeta({
    required this.sessionId,
    required this.turma,
    required this.inicio,
    this.fim,
    required this.alunos,
  });

  final String sessionId;
  final String turma;
  final DateTime inicio;
  final DateTime? fim;
  final Set<String> alunos;

  Map<String, dynamic> toMap() => {
        'turma': turma,
        'inicio': inicio.millisecondsSinceEpoch,
        if (fim != null) 'fim': fim!.millisecondsSinceEpoch,
        'alunos': alunos.toList(),
      };

  static AulaMeta? fromMap(String sessionId, dynamic m) {
    if (m is! Map) return null;
    final inicio = (m['inicio'] as num?)?.toInt();
    final turma = m['turma'];
    if (inicio == null || turma is! String) return null;
    final fim = (m['fim'] as num?)?.toInt();
    final alunos = <String>{};
    if (m['alunos'] is List) {
      for (final a in m['alunos'] as List) {
        if (a is String && a.isNotEmpty) alunos.add(a);
      }
    }
    return AulaMeta(
      sessionId: sessionId,
      turma: turma,
      inicio: DateTime.fromMillisecondsSinceEpoch(inicio),
      fim: fim != null ? DateTime.fromMillisecondsSinceEpoch(fim) : null,
      alunos: alunos,
    );
  }
}

class HistoryStore {
  HistoryStore({
    required this.teacherUid,
    required this.crypto,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final String teacherUid;
  final SessionCrypto crypto;
  final FirebaseDatabase _db;

  String? _sessionId;
  AulaMeta? _metaAtual;

  DatabaseReference get _raiz => _db.ref('history/$teacherUid');

  // ---- Gravação (durante a aula) --------------------------------------------------

  /// Abre (ou re-anexa a) sessão da aula. Chamado no iniciarAula e no start()
  /// do app quando há aula ativa persistida.
  Future<void> abrirSessao(String turma, int inicioMs) async {
    _sessionId = '$inicioMs';
    // Re-anexa: se a meta já existe (app reaberto no meio da aula), preserva
    // a lista de alunos já registrada.
    final existente = await _lerMeta(_sessionId!);
    _metaAtual = existente ??
        AulaMeta(
          sessionId: _sessionId!,
          turma: turma,
          inicio: DateTime.fromMillisecondsSinceEpoch(inicioMs),
          alunos: {},
        );
    if (existente == null) await _gravarMeta();
  }

  /// Registra eventos de um aluno na sessão aberta.
  Future<void> registrar(String aluno, List<NavEvent> eventos) async {
    final sid = _sessionId;
    final meta = _metaAtual;
    if (sid == null || meta == null || eventos.isEmpty) return;
    try {
      final env = await crypto.seal({
        'aluno': aluno,
        'eventos': [
          for (final e in eventos) {'url': e.url, 'title': e.title, 'ts': e.ts},
        ],
      });
      await _raiz.child('$sid/ev').push().set(env);
      if (meta.alunos.add(aluno)) await _gravarMeta();
    } catch (e) {
      debugPrint('[CdA] registro de histórico falhou: $e');
    }
  }

  Future<void> fecharSessao() async {
    final meta = _metaAtual;
    if (meta == null) return;
    _metaAtual = AulaMeta(
      sessionId: meta.sessionId,
      turma: meta.turma,
      inicio: meta.inicio,
      fim: DateTime.now(),
      alunos: meta.alunos,
    );
    await _gravarMeta();
    _sessionId = null;
    _metaAtual = null;
  }

  Future<void> _gravarMeta() async {
    final meta = _metaAtual;
    final sid = _sessionId;
    if (meta == null || sid == null) return;
    try {
      await _raiz.child('$sid/meta').set(await crypto.seal(meta.toMap()));
    } catch (e) {
      debugPrint('[CdA] meta do histórico falhou: $e');
    }
  }

  // ---- Consulta -------------------------------------------------------------------

  Future<AulaMeta?> _lerMeta(String sessionId) async {
    try {
      final v = (await _raiz.child('$sessionId/meta').get()).value;
      if (v is! String) return null;
      return AulaMeta.fromMap(sessionId, await crypto.open(v));
    } catch (_) {
      return null; // indecifrável (outra instalação) ou ausente
    }
  }

  /// Todas as sessões legíveis, mais recentes primeiro. `indecifraveis`
  /// (out) recebe os sessionIds que não abriram com esta chave.
  Future<List<AulaMeta>> listarSessoes({List<String>? indecifraveis}) async {
    final snap = await _raiz.get();
    final v = snap.value;
    final metas = <AulaMeta>[];
    if (v is Map) {
      for (final entry in v.entries) {
        final sid = entry.key.toString();
        final node = entry.value;
        final env = node is Map ? node['meta'] : null;
        if (env is! String) continue;
        try {
          final meta = AulaMeta.fromMap(sid, await crypto.open(env));
          if (meta != null) {
            metas.add(meta);
            continue;
          }
        } catch (_) {
          // cai no indecifráveis
        }
        indecifraveis?.add(sid);
      }
    }
    metas.sort((a, b) => b.inicio.compareTo(a.inicio));
    return metas;
  }

  /// Aulas em que o aluno aparece, mais recentes primeiro.
  Future<List<AulaMeta>> aulasDoAluno(String aluno) async {
    final todas = await listarSessoes();
    return todas.where((m) => m.alunos.contains(aluno)).toList();
  }

  /// Eventos do aluno numa sessão, ordenados por ts.
  Future<List<NavEvent>> eventosDoAluno(String sessionId, String aluno) async {
    final snap = await _raiz.child('$sessionId/ev').get();
    final v = snap.value;
    final eventos = <NavEvent>[];
    if (v is Map) {
      for (final env in v.values) {
        if (env is! String) continue;
        try {
          final m = await crypto.open(env);
          if (m['aluno'] != aluno) continue;
          final lista = m['eventos'];
          if (lista is List) {
            for (final e in lista) {
              final ev = NavEvent.fromMap(e);
              if (ev != null) eventos.add(ev);
            }
          }
        } catch (_) {
          // chunk indecifrável — pula
        }
      }
    }
    eventos.sort((a, b) => a.ts.compareTo(b.ts));
    return eventos;
  }

  // ---- Apagar (manual) --------------------------------------------------------------

  Future<void> apagarSessao(String sessionId) async {
    await _raiz.child(sessionId).remove();
    if (_sessionId == sessionId) {
      _sessionId = null;
      _metaAtual = null;
    }
  }

  /// Remove os registros de UM aluno em todas as aulas (chunks dele + meta);
  /// sessões que ficarem sem alunos são removidas por inteiro.
  Future<void> apagarAluno(String aluno) async {
    final metas = await listarSessoes();
    for (final meta in metas) {
      if (!meta.alunos.contains(aluno)) continue;
      final snap = await _raiz.child('${meta.sessionId}/ev').get();
      final v = snap.value;
      if (v is Map) {
        for (final entry in v.entries) {
          final env = entry.value;
          if (env is! String) continue;
          try {
            final m = await crypto.open(env);
            if (m['aluno'] == aluno) {
              await _raiz.child('${meta.sessionId}/ev/${entry.key}').remove();
            }
          } catch (_) {
            // indecifrável — deixa
          }
        }
      }
      final restantes = {...meta.alunos}..remove(aluno);
      if (restantes.isEmpty) {
        await apagarSessao(meta.sessionId);
      } else {
        final nova = AulaMeta(
          sessionId: meta.sessionId,
          turma: meta.turma,
          inicio: meta.inicio,
          fim: meta.fim,
          alunos: restantes,
        );
        await _raiz
            .child('${meta.sessionId}/meta')
            .set(await crypto.seal(nova.toMap()));
        if (_sessionId == meta.sessionId) _metaAtual = nova;
      }
    }
  }

  Future<void> apagarTudo() async {
    await _raiz.remove();
    _sessionId = null;
    _metaAtual = null;
  }
}
