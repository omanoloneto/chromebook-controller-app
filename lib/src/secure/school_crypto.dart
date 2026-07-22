// Chave dos stores compartilhados do workspace — derivada da keypair da
// ESCOLA (HKDF com info própria). Determinística: mesma keypair ⇒ mesma
// chave; todo professor que adotou a keypair da escola decifra
// /school/stores e /school/aulas (envelopes opacos no banco).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'keypair.dart';

final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final List<int> _salt = utf8.encode('controle-de-aula');
final List<int> _info = utf8.encode('school-store-v1');

/// Deriva a chave de 32 bytes dos stores da escola e devolve o cifrador
/// pronto (mesmo envelope AES-256-GCM do transporte).
Future<SessionCrypto> schoolCryptoFrom(DeviceKeyPair escola) async {
  final priv = await escola.privateBytes();
  final sk = await _hkdf.deriveKey(
    secretKey: SecretKey(priv),
    nonce: _salt,
    info: _info,
  );
  return SessionCrypto(await sk.extractBytes());
}
