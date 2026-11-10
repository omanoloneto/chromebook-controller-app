// Login entregue ao app do Celita OS (protocolo §2.1): o QR dele traz uma
// chave efêmera e um canal; este celular cifra um id_token fresco do Google e
// a chave do professor para essa chave e grava em /handoff/{canal}. O Celita
// entra na mesma conta Firebase e adota a chave — vira o mesmo professor
// deste celular, sem cliente OAuth no PC.

import 'dart:convert';
import 'dart:math';

import '../backend/backend.dart';
import '../secure/crypto.dart';
import '../secure/keypair.dart';
import 'qr_payload.dart';

const int kMaxHandoffKeys = 200;
const int kMaxTeacherName = 40;

/// O que o celular entregou ao computador.
typedef LoginGrant = ({String idToken, String keys, String? teacherName, String? schoolUid});

/// Lado do computador: canal e chave efêmera do QR, e a abertura do que o
/// celular gravar nele.
class LoginRequest {
  LoginRequest._(this._ephemeral, this.channel);

  final DeviceKeyPair _ephemeral;
  final String channel;

  static Future<LoginRequest> create({Random? random}) async {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return LoginRequest._(await DeviceKeyPair.generate(), pubToB64url(bytes));
  }

  String get path => 'handoff/$channel';

  String get qrPayload => jsonEncode({
        'v': 1,
        't': 'login',
        'c': channel,
        'pub': pubToB64url(_ephemeral.publicBytes),
      });

  /// null = o nó não é uma entrega válida para esta chave.
  Future<LoginGrant?> open(Object? node) async {
    if (node is! Map) return null;
    final pub = node['pub'], env = node['env'];
    if (pub is! String || env is! String) return null;
    final Map<String, dynamic> message;
    try {
      final key = await _ephemeral.deriveSessionKey(pubFromB64url(pub));
      message = await SessionCrypto(key).open(env);
    } catch (_) {
      return null;
    }
    if (message['v'] != 1) return null;
    final idToken = message['idToken'], keys = message['keys'];
    if (idToken is! String || idToken.isEmpty) return null;
    if (keys is! String || keys.isEmpty || keys.length > kMaxHandoffKeys) return null;
    final name = message['teacherName'], school = message['schoolUid'];
    final trimmed = name is String ? name.trim() : '';
    return (
      idToken: idToken,
      keys: keys,
      teacherName: trimmed.isEmpty
          ? null
          : trimmed.substring(0, min(trimmed.length, kMaxTeacherName)),
      schoolUid: school is String && school.isNotEmpty ? school : null,
    );
  }
}

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
    RealtimeDb? database,
  }) async {
    final db = database ?? Backend.instance.db;
    await db.ref('handoff/${qr.channel}').set({
      ...payload,
      'ts': ServerValue.timestamp,
    });
  }
}
