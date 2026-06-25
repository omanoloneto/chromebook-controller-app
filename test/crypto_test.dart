// Paridade da criptografia com a extensão (src/lib/crypto.js).
// O envelope esperado abaixo foi gerado pelo lado JS (Web Crypto) com a MESMA
// chave/nonce/plaintext. Se este teste quebrar, o formato divergiu dos dois
// lados e o pareamento real vai falhar.

import 'package:cryptography/cryptography.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Vetor fixo: key = 0..31, nonce = 0..11, plaintext = {"msg":"oi","seq":1}.
  final key = List<int>.generate(32, (i) => i);
  final nonce = List<int>.generate(12, (i) => i);
  const esperadoDoJs = 'AAECAwQFBgcICQoLPCC7aKLH+DniKLWnk5odHKHstkkVOvyLJf2VX518YSPQP09+';

  test('seal casa byte a byte com o lado JS (Web Crypto)', () async {
    final c = SessionCrypto(key);
    final sealed = await c.seal({'msg': 'oi', 'seq': 1}, nonce: nonce);
    expect(sealed, esperadoDoJs);
  });

  test('open reverte o seal (round-trip)', () async {
    final c = SessionCrypto(key);
    final sealed = await c.seal({'msg': 'oi', 'seq': 1});
    final back = await c.open(sealed);
    expect(back['msg'], 'oi');
    expect(back['seq'], 1);
  });

  test('open com chave errada falha (autenticação GCM)', () async {
    final emissor = SessionCrypto(key);
    final sealed = await emissor.seal({'msg': 'oi'});
    final outraChave = SessionCrypto(List<int>.generate(32, (i) => 255 - i));
    expect(
      () => outraChave.open(sealed),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
