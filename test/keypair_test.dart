// Paridade do handshake X25519+HKDF com a extensão (src/lib/keypair.js).
// A chave de sessão esperada foi gerada pelo lado JS (Web Crypto) com os MESMOS
// pares de chaves fixos. Se quebrar, o handshake divergiu e o vínculo TOFU falha.

import 'dart:convert';

import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _b64url(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}

void main() {
  // Pares fixos (base64url): A = professor, B = PC.
  const aD = 'kLHtc7YxBsgOOgdkfgd50vy_eGvUACVycVkOsUiQX3Q';
  const aX = 'Z03jzVY4eGibMJbdDlyaM-hjbo7agkCE7LSiORqfChM';
  const bD = 'WLMjlWRflQMiHmzsgnJ1jfWuJOHhqyBy0YS4x0dnbmQ';
  const bX = 'JS-rAkqU_z8Q6eeqM32bnG47qUM0a2Iuatbgo_-24GQ';
  const esperadoDoJs = 'REyf1iv4s/Kj9xpKPzYr2HH/nHMFI0g4A8qQ7CH+SF8=';

  test('chave de sessão casa com o lado JS', () async {
    final a = await DeviceKeyPair.fromBytes(_b64url(aD), _b64url(aX));
    final sk = await a.deriveSessionKey(_b64url(bX));
    expect(base64.encode(sk), esperadoDoJs);
  });

  test('ECDH é simétrico (A↔B derivam a mesma chave)', () async {
    final a = await DeviceKeyPair.fromBytes(_b64url(aD), _b64url(aX));
    final b = await DeviceKeyPair.fromBytes(_b64url(bD), _b64url(bX));
    final skA = await a.deriveSessionKey(_b64url(bX));
    final skB = await b.deriveSessionKey(_b64url(aX));
    expect(base64.encode(skA), base64.encode(skB));
  });
}
