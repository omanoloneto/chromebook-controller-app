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

  test('o pedido do computador abre o que o celular montou para o QR dele', () async {
    final request = await LoginRequest.create();
    final qr = QrLoginPayload.parse(request.qrPayload)!;
    expect(qr.channel, request.channel);
    expect(request.path, 'handoff/${request.channel}');
    expect(request.channel.length, greaterThanOrEqualTo(22));
    expect((await LoginRequest.create()).channel, isNot(request.channel));

    final node = await LoginHandoff.montar(
      qr: qr,
      idToken: 'id.tok.en',
      keys: 'priv:pub',
      teacherName: '  ${'N' * 60}  ',
      schoolUid: 'uid-escola',
    );
    final grant = await request.open({...node, 'ts': 1});
    expect(grant!.idToken, 'id.tok.en');
    expect(grant.keys, 'priv:pub');
    expect(grant.teacherName, 'N' * kMaxTeacherName);
    expect(grant.schoolUid, 'uid-escola');

    final alone = await request.open(
      await LoginHandoff.montar(qr: qr, idToken: 't', keys: 'k', teacherName: ' '),
    );
    expect(alone!.teacherName, isNull);
    expect(alone.schoolUid, isNull);

    // Fora do contrato: nó torto, chave de outro pedido, campos vazios ou grandes.
    final other = await LoginRequest.create();
    expect(await other.open(node), isNull);
    for (final bad in [null, 'texto', {'pub': node['pub']}, {'pub': 1, 'env': node['env']}]) {
      expect(await request.open(bad), isNull);
    }
    for (final (idToken, keys) in [('', 'k'), ('t', ''), ('t', 'k' * (kMaxHandoffKeys + 1))]) {
      final torto = await LoginHandoff.montar(qr: qr, idToken: idToken, keys: keys, teacherName: 'Ana');
      expect(await request.open(torto), isNull);
    }
  });
}
