// Criptografia ponta-a-ponta dos comandos — ver docs/protocolo.md.
// Precisa casar EXATAMENTE com a extensão (src/lib/crypto.js).
//
// Formato no fio (base64 padrão): nonce(12) || ciphertext || tag(16)
// Cifra: AES-256-GCM. Texto em claro: JSON UTF-8.
// SEM AAD — seq/ts viajam dentro do JSON (já autenticado pelo GCM).

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class SessionCrypto {
  SessionCrypto(this.key);

  /// Chave de 32 bytes (256 bits).
  final List<int> key;

  final AesGcm _algo = AesGcm.with256bits();
  SecretKey? _sk;

  Future<SecretKey> _secretKey() async =>
      _sk ??= await _algo.newSecretKeyFromBytes(key);

  /// Gera uma chave aleatória de 32 bytes.
  static List<int> generateKey() {
    final r = Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256));
  }

  static String keyToBase64url(List<int> key) =>
      base64Url.encode(key).replaceAll('=', '');

  static List<int> keyFromBase64url(String s) {
    final clean = s.trim();
    final pad = (4 - clean.length % 4) % 4;
    return base64Url.decode(clean + ('=' * pad));
  }

  /// Cifra um objeto. `nonce` opcional só para testes determinísticos.
  Future<String> seal(Map<String, dynamic> obj, {List<int>? nonce}) async {
    final n = nonce ?? _algo.newNonce();
    final plaintext = utf8.encode(jsonEncode(obj));
    final box = await _algo.encrypt(
      plaintext,
      secretKey: await _secretKey(),
      nonce: n,
    );
    final out = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return base64.encode(out);
  }

  /// Decifra um envelope (base64). Lança em caso de falha de autenticação.
  Future<Map<String, dynamic>> open(String envelopeB64) async {
    final bytes = base64.decode(envelopeB64.trim());
    if (bytes.length < 12 + 16) {
      throw const FormatException('envelope_curto');
    }
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(12, bytes.length - 16);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final plaintext = await _algo.decrypt(box, secretKey: await _secretKey());
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }
}
