// Handshake de chaves (TOFU) — ver docs/protocolo.md.
// X25519 (ECDH) + HKDF-SHA256 -> chave de sessão de 32 bytes para o AES-256-GCM.
// Precisa casar EXATAMENTE com a extensão (src/lib/keypair.js).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _x25519 = X25519();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final List<int> _salt = utf8.encode('controle-de-aula');
final List<int> _info = utf8.encode('session-key-v3');

String pubToB64url(List<int> pub) => base64Url.encode(pub).replaceAll('=', '');

List<int> pubFromB64url(String s) {
  final clean = s.trim();
  final pad = (4 - clean.length % 4) % 4;
  return base64Url.decode(clean + ('=' * pad));
}

/// Par de chaves de longo prazo do aparelho (professor).
class DeviceKeyPair {
  DeviceKeyPair._(this._keyPair, this.publicBytes);

  final SimpleKeyPair _keyPair;
  final List<int> publicBytes; // 32 bytes

  static Future<DeviceKeyPair> generate() async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    return DeviceKeyPair._(kp, pub.bytes);
  }

  /// Reconstrói a partir dos bytes guardados (privado 32, público 32).
  static Future<DeviceKeyPair> fromBytes(List<int> priv, List<int> pub) async {
    final kp = SimpleKeyPairData(
      priv,
      publicKey: SimplePublicKey(pub, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    return DeviceKeyPair._(kp, pub);
  }

  Future<List<int>> privateBytes() => _keyPair.extractPrivateKeyBytes();

  /// Deriva a chave de sessão AES (32 bytes) com a pubkey do par remoto.
  Future<List<int>> deriveSessionKey(List<int> peerPublicBytes) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey:
          SimplePublicKey(peerPublicBytes, type: KeyPairType.x25519),
    );
    final sk = await _hkdf.deriveKey(secretKey: shared, nonce: _salt, info: _info);
    return sk.extractBytes();
  }
}
