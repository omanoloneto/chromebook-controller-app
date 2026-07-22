// Chave/identidade do workspace da escola em /school/{meta,keypair}.
// Modelo ABERTO (decisão do usuário): qualquer login Google do app lê a chave
// e entra — risco aceito; a proteção contra terceiros é o gate GOOGLE nas
// rules. Create-once: nem professor sobrescreve a chave (troca = console).

import 'package:firebase_database/firebase_database.dart';

import '../secure/key_store.dart';

class SchoolInfo {
  const SchoolInfo({required this.keys, required this.schoolUid});

  final String keys; // "priv:pub" (b64url), formato do teacher_key.txt
  final String schoolUid; // uid do fundador — dono de bind/history/wallpaper
}

class SchoolKeys {
  SchoolKeys({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Publica a keypair local como a chave da escola (fundador, 1x).
  /// Idempotente: escola já criada com a MESMA chave = ok; com outra = erro.
  Future<String?> publicar(String uid) async {
    final minhas = await KeyStore.lerBruto();
    if (minhas == null) return 'Chave local ainda não existe — reabra o app.';
    final existente = await baixar();
    if (existente != null) {
      return existente.keys == minhas
          ? null
          : 'A escola já foi criada por outro professor — use "Entrar".';
    }
    await _db.ref('school/meta').set({
      'schoolUid': uid,
      'criadoEm': ServerValue.timestamp,
    });
    await _db.ref('school/keypair').set({
      'keys': minhas,
      'ts': ServerValue.timestamp,
    });
    return null;
  }

  /// Lê a escola publicada (null = ainda não criada).
  Future<SchoolInfo?> baixar() async {
    final keys = (await _db.ref('school/keypair/keys').get()).value;
    final uid = (await _db.ref('school/meta/schoolUid').get()).value;
    if (keys is! String || uid is! String) return null;
    return SchoolInfo(keys: keys, schoolUid: uid);
  }

  /// Adota a chave da escola como a keypair local deste celular.
  Future<void> adotar(SchoolInfo escola) => KeyStore.salvarBruto(escola.keys);
}
