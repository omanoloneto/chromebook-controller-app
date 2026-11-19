// Equipe da escola (docs/protocolo.md §3.2): quem abriu o app, professor ou
// monitora, para o aluno escolher com quem falar no chat do Celita. Cada um
// grava só a própria entrada; "visto" marca quem está com o app aberto.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../backend/backend.dart';
import 'school_members.dart';

const Duration kVistoNaEquipe = Duration(minutes: 5);
const int kMaxNomeNaEquipe = 60;

enum PapelNaEquipe { professor, monitora }

class PresencaNaEquipe {
  PresencaNaEquipe({
    required this.papel,
    required this.uid,
    required this.email,
    required this.nome,
    RealtimeDb? database,
    this.intervalo = kVistoNaEquipe,
  }) : _db = database ?? Backend.instance.db;

  final PapelNaEquipe papel;
  final String uid;
  final String email;

  /// Lido a cada gravação: o nome pode mudar em Ajustes com o app aberto.
  final String Function() nome;
  final Duration intervalo;
  final RealtimeDb _db;
  Timer? _timer;

  Future<void> iniciar() async {
    _timer?.cancel();
    _timer = Timer.periodic(intervalo, (_) => unawaited(gravar()));
    await gravar();
  }

  Future<void> gravar() async {
    final n = nome().trim();
    try {
      await _db.ref('school/equipe/$uid').set({
        'nome': n.isEmpty ? _padrao : (n.length > kMaxNomeNaEquipe ? n.substring(0, kMaxNomeNaEquipe) : n),
        'papel': papel.name,
        'ek': emailKey(email),
        'visto': ServerValue.timestamp,
      });
    } on FirebaseException catch (e) {
      debugPrint('[CdA] equipe: ${e.code}');
    }
  }

  String get _padrao => papel == PapelNaEquipe.monitora ? 'Monitora' : 'Professor';

  void parar() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Fundador tirou o acesso de alguém: a entrada some da lista dos PCs.
Future<void> tirarDaEquipe(String email, {RealtimeDb? database}) async {
  final db = database ?? Backend.instance.db;
  final chave = emailKey(email.trim());
  try {
    final todos = (await db.ref('school/equipe').get()).value;
    if (todos is! Map) return;
    for (final entry in todos.entries) {
      final v = entry.value;
      if (v is Map && v['ek'] == chave) await db.ref('school/equipe/${entry.key}').remove();
    }
  } on FirebaseException catch (e) {
    debugPrint('[CdA] tirar da equipe: ${e.code}');
  }
}
