// Login entregue ao Celita OS: o QR dele é reconhecido, e o envelope que o
// celular grava abre do lado do computador com a chave efêmera do QR
// (mesma derivação X25519+HKDF das sessões — paridade com handoff.py).

import 'package:controle_de_aula/src/cloud/login_handoff.dart';
import 'package:controle_de_aula/src/cloud/qr_payload.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QrLoginPayload aceita só o QR de login v1', () {
    final qr = QrLoginPayload.parse('{"v":1,"t":"login","c":"canal123","pub":"AAAA"}');
    expect(qr, isNotNull);
    expect(qr!.channel, 'canal123');
    expect(qr.pub, 'AAAA');
    for (final raw in [
      '{"v":4,"id":"d1","pub":"P","tok":"T"}',
      '{"v":1,"t":"outro","c":"x","pub":"y"}',
      '{"v":1,"t":"login","c":"","pub":"y"}',
      '{"v":1,"t":"login","c":"x"}',
      'lixo',
      '',
    ]) {
      expect(QrLoginPayload.parse(raw), isNull, reason: raw);
    }
    // O QR de login nunca passa por engano como pareamento.
    expect(QrPairPayload.parse('{"v":1,"t":"login","c":"x","pub":"y"}'), isNull);
  });

  test('o computador abre o envelope com a chave efêmera do QR', () async {
    final celita = await DeviceKeyPair.generate();
    final qr = QrLoginPayload(channel: 'c1', pub: pubToB64url(celita.publicBytes));
    final payload = await LoginHandoff.montar(
      qr: qr,
      idToken: 'id.tok.en',
      keys: 'priv:pub',
      teacherName: 'Ana',
      schoolUid: 'uid-escola',
    );
    expect(payload.keys, containsAll(['pub', 'env']));
    final chave = await celita.deriveSessionKey(pubFromB64url(payload['pub'] as String));
    final aberto = await SessionCrypto(chave).open(payload['env'] as String);
    expect(aberto, {
      'v': 1,
      'idToken': 'id.tok.en',
      'keys': 'priv:pub',
      'teacherName': 'Ana',
      'schoolUid': 'uid-escola',
    });
    // Sem escola o campo não vai (o Celita fica em modo isolado).
    final isolado = await LoginHandoff.montar(qr: qr, idToken: 't', keys: 'k', teacherName: 'Ana');
    final chaveIsolada = await celita.deriveSessionKey(pubFromB64url(isolado['pub'] as String));
    final abertoIsolado = await SessionCrypto(chaveIsolada).open(isolado['env'] as String);
    expect(abertoIsolado.containsKey('schoolUid'), isFalse);
    // Outra chave não abre.
    final outro = await DeviceKeyPair.generate();
    final errada = await outro.deriveSessionKey(pubFromB64url(payload['pub'] as String));
    await expectLater(SessionCrypto(errada).open(payload['env'] as String), throwsA(anything));
  });
}
