// Chave/identidade do workspace da escola em /school/{meta,keypair}.
// Escola fechada: só o fundador e os e-mails liberados em /school/members
// leem a chave (school_members.dart). Create-once: nem professor sobrescreve
// a chave (troca = console).

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
    const outro = 'A escola já foi criada por outro professor — use "Entrar".';
    final fundador = await schoolUidPublicado();
    if (fundador != null && fundador != uid) return outro;
    if (fundador == uid) {
      // Meta já gravada por mim: falta só a keypair se a 1ª tentativa caiu
      // entre as duas escritas.
      final existente = await baixar();
      if (existente != null) return existente.keys == minhas ? null : outro;
    } else {
      await _db.ref('school/meta').set({
        'schoolUid': uid,
        'criadoEm': ServerValue.timestamp,
      });
    }
    await _db.ref('school/keypair').set({
      'keys': minhas,
      'ts': ServerValue.timestamp,
    });
    return null;
  }

  /// uid do fundador (null = escola ainda não criada). Qualquer conta Google
  /// lê — é o que separa "não há escola" de "não liberado".
  Future<String?> schoolUidPublicado() async {
    final uid = (await _db.ref('school/meta/schoolUid').get()).value;
    return uid is String ? uid : null;
  }

  /// Lê a escola publicada (null = ainda não criada). A keypair só é lida
  /// com a meta presente; quem não é membro leva permission-denied nela.
  Future<SchoolInfo?> baixar() async {
    final uid = await schoolUidPublicado();
    if (uid == null) return null;
    final keys = (await _db.ref('school/keypair/keys').get()).value;
    if (keys is! String) return null;
    return SchoolInfo(keys: keys, schoolUid: uid);
  }

  /// Adota a chave da escola como a keypair local deste celular.
  Future<void> adotar(SchoolInfo escola) => KeyStore.salvarBruto(escola.keys);
}
