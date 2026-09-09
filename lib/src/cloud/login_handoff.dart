// Login entregue ao app do Celita OS (protocolo §2.1): o QR dele traz uma
// chave efêmera e um canal; este celular cifra um id_token fresco do Google e
// a chave do professor para essa chave e grava em /handoff/{canal}. O Celita
// entra na mesma conta Firebase e adota a chave — vira o mesmo professor
// deste celular, sem cliente OAuth no PC.

import 'package:firebase_database/firebase_database.dart';

import '../secure/crypto.dart';
import '../secure/keypair.dart';
import 'qr_payload.dart';

class LoginHandoff {
  /// Parte pura: {pub, env} prontos para o canal.
  static Future<Map<String, dynamic>> montar({
    required QrLoginPayload qr,
    required String idToken,
    required String keys,
    required String teacherName,
    String? schoolUid,
  }) async {
    final efemera = await DeviceKeyPair.generate();
    final chave = await efemera.deriveSessionKey(pubFromB64url(qr.pub));
    final env = await SessionCrypto(chave).seal({
      'v': 1,
      'idToken': idToken,
      'keys': keys,
      'teacherName': teacherName,
      if (schoolUid != null) 'schoolUid': schoolUid,
    });
    return {'pub': pubToB64url(efemera.publicBytes), 'env': env};
  }

  static Future<void> entregar(
    QrLoginPayload qr,
    Map<String, dynamic> payload, {
    FirebaseDatabase? database,
  }) async {
    final db = database ?? FirebaseDatabase.instance;
    await db.ref('handoff/${qr.channel}').set({
      ...payload,
      'ts': ServerValue.timestamp,
    });
  }
}
