// Chave do histórico de aulas — derivada da keypair do professor (HKDF com
// info própria). Determinística: mesma keypair ⇒ mesma chave; SÓ este celular
// decifra o que sobe para /history (o banco carrega envelopes opacos).
// Reinstalar o app (keypair nova) torna o histórico antigo indecifrável.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'keypair.dart';

final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final List<int> _salt = utf8.encode('controle-de-aula');
final List<int> _info = utf8.encode('history-key-v1');

/// Deriva a chave de 32 bytes do histórico a partir da chave privada do
/// professor e devolve o cifrador pronto (mesmo envelope AES-256-GCM do
/// transporte).
Future<SessionCrypto> historyCryptoFrom(DeviceKeyPair teacher) async {
  final priv = await teacher.privateBytes();
  final sk = await _hkdf.deriveKey(
    secretKey: SecretKey(priv),
    nonce: _salt,
    info: _info,
  );
  return SessionCrypto(await sk.extractBytes());
}
