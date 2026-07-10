// Backup por PIN: PIN certo abre; PIN errado falha; salt aleatório por blob.

import 'dart:convert';

import 'package:controle_de_aula/src/secure/pin_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PIN certo decifra o que selou', () async {
    final blob = await selarComPin('123456', {'keypair': 'abc:def'});
    final aberto = await abrirComPin('123456', blob);
    expect(aberto['keypair'], 'abc:def');
  });

  test('PIN errado NÃO decifra', () async {
    final blob = await selarComPin('123456', {'x': 1});
    expect(() => abrirComPin('000000', blob), throwsA(anything));
  });

  test('salt aleatório: mesmo PIN + dados geram blobs diferentes', () async {
    final b1 = await selarComPin('123456', {'x': 1});
    final b2 = await selarComPin('123456', {'x': 1});
    expect(b1, isNot(b2));
    // Mas ambos abrem.
    expect((await abrirComPin('123456', b1))['x'], 1);
    expect((await abrirComPin('123456', b2))['x'], 1);
  });

  test('blob carrega salt separado do envelope', () async {
    final blob = await selarComPin('123456', {'x': 1});
    final m = jsonDecode(blob) as Map<String, dynamic>;
    expect(m.keys.toSet(), {'salt', 'env'});
  });
}
