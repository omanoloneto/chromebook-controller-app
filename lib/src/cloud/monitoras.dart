// Monitoras da escola (docs/protocolo.md §3.1): o fundador libera e-mails em
// /school/monitores e guarda a chave da monitora em /school/monitorKey; os
// professores publicam a pub dela em devices/{id}/mon/pub de cada PC.
// A monitora nunca recebe a chave da escola.

import 'package:flutter/foundation.dart' show debugPrint;

import '../backend/backend.dart';
import '../secure/keypair.dart';
import 'equipe.dart';
import 'school_members.dart';

/// "priv:pub" em base64url, o mesmo formato da chave da escola.
Future<String> chaveEmTexto(DeviceKeyPair par) async =>
    '${pubToB64url(await par.privateBytes())}:${pubToB64url(par.publicBytes)}';

Future<DeviceKeyPair?> chaveDoTexto(Object? texto) async {
  if (texto is! String) return null;
  final partes = texto.split(':');
  if (partes.length != 2) return null;
  try {
    final par = await DeviceKeyPair.fromPrivate(pubFromB64url(partes[0]));
    return pubToB64url(par.publicBytes) == partes[1] ? par : null;
  } catch (_) {
    return null;
  }
}

class SchoolMonitoras {
  SchoolMonitoras({RealtimeDb? database})
      : _db = database ?? Backend.instance.db;

  final RealtimeDb _db;

  DbRef get _lista => _db.ref('school/monitores');
  DbRef get _chave => _db.ref('school/monitorKey');

  /// A própria entrada existe? permission-denied = não é monitora.
  Future<bool> liberada(String email) async {
    try {
      return (await _lista.child(emailKey(email)).get()).value == true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  Stream<List<String>> emails() => _lista.onValue.map((e) {
        final v = e.snapshot.value;
        return <String>[
          if (v is Map)
            for (final entry in v.entries)
              if (entry.value == true) emailDaChave('${entry.key}'),
        ]..sort();
      });

  /// Só o fundador: libera o e-mail e cria a chave da monitora na primeira vez.
  Future<String?> adicionar(String email) async {
    final e = normalizarEmail(email);
    if (e == null) return 'E-mail inválido. Confira e tente de novo.';
    await garantirChave();
    await _lista.child(emailKey(e)).set(true);
    return null;
  }

  Future<void> remover(String email) async {
    await _lista.child(emailKey(email.trim().toLowerCase())).remove();
    await tirarDaEquipe(email, database: _db);
  }

  Future<DeviceKeyPair?> baixarChave() async =>
      chaveDoTexto((await _chave.child('keys').get()).value);

  Future<DeviceKeyPair> garantirChave() async {
    final atual = await baixarChave();
    if (atual != null) return atual;
    final nova = await DeviceKeyPair.generate();
    await _chave.set({'keys': await chaveEmTexto(nova), 'ts': ServerValue.timestamp});
    return nova;
  }

  /// Professor liberado: grava a pub da monitora nos PCs da escola que ainda
  /// não a têm. Sem chave criada (nenhuma monitora), não faz nada.
  Future<int> publicarNosPcs() async {
    final String pub;
    try {
      final par = await baixarChave();
      if (par == null) return 0;
      pub = pubToB64url(par.publicBytes);
    } on FirebaseException catch (e) {
      debugPrint('[CdA] chave da monitora: ${e.code}');
      return 0;
    }
    final roster = (await _db.ref('school/devices').get()).value;
    var gravados = 0;
    if (roster is! Map) return 0;
    for (final entry in roster.entries) {
      if (entry.value != true) continue;
      final ref = _db.ref('devices/${entry.key}/mon/pub');
      try {
        if ((await ref.get()).value == pub) continue;
        await ref.set(pub);
        gravados++;
      } on FirebaseException catch (e) {
        debugPrint('[CdA] mon/pub de ${entry.key}: ${e.code}');
      }
    }
    return gravados;
  }
}
