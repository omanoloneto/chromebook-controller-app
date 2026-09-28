// Escola fechada: só entra quem o fundador liberou em /school/members/{chave}.
// A chave é o e-mail em minúsculas com "." trocado por "," (o RTDB não aceita
// "." em chaves) — a mesma conta das rules e do agente/GTK do Celita.

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// "Ana.Silva@escola.com.br" → "ana,silva@escola,com,br".
String emailKey(String email) => email.toLowerCase().replaceAll('.', ',');

/// Inverso de [emailKey], só para exibir.
String emailDaChave(String key) => key.replaceAll(',', '.');

// Espelha o .validate de school/members/$email nas rules.
final RegExp _chaveValida = RegExp(r"^[a-z0-9,_+'-]+@[a-z0-9,-]+$");

/// E-mail já normalizado (sem espaços nas pontas, minúsculas) ou null se não
/// pode virar chave: `$ # [ ] /`, espaço e outros caracteres ficam de fora.
String? normalizarEmail(String email) {
  final e = email.trim().toLowerCase();
  if (e.isEmpty || !_chaveValida.hasMatch(emailKey(e))) return null;
  return e;
}

/// Texto único (app e GTK) para quem ainda não foi liberado.
String textoNaoLiberado(String? email) =>
    'Seu e-mail (${email ?? 'sem e-mail'}) ainda não foi liberado. Peça ao '
    'professor que criou a escola para liberar em Ajustes → Professores da '
    'escola.';

/// Checagem ao abrir o app: só "não liberado" barra. Falha de rede ou demora
/// deixa seguir — as rules barram no servidor e o roster negado avisa depois.
Future<bool> liberadoAoAbrir(
  Future<bool> Function() consultar, {
  Duration limite = const Duration(seconds: 10),
}) async {
  try {
    return await consultar().timeout(limite);
  } catch (e) {
    debugPrint('[CdA] checagem de membro falhou, seguindo: $e');
    return true;
  }
}

class SchoolMembers {
  SchoolMembers({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference get _ref => _db.ref('school/members');

  /// A própria entrada existe? permission-denied = não liberado; outras
  /// falhas (rede) sobem.
  Future<bool> liberado(String email) async {
    try {
      return (await _ref.child(emailKey(email)).get()).value == true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  /// E-mails liberados, em ordem (só o fundador e membros leem).
  Stream<List<String>> emails() => _ref.onValue.map((e) {
        final v = e.snapshot.value;
        final lista = <String>[
          if (v is Map)
            for (final entry in v.entries)
              if (entry.value == true) emailDaChave('${entry.key}'),
        ]..sort();
        return lista;
      });

  /// Libera um e-mail (só o fundador escreve). Null = ok.
  Future<String?> adicionar(String email) async {
    final e = normalizarEmail(email);
    if (e == null) return 'E-mail inválido. Confira e tente de novo.';
    await _ref.child(emailKey(e)).set(true);
    return null;
  }

  Future<void> remover(String email) => _ref.child(emailKey(email)).remove();
}
