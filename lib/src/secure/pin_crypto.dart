// Cifra por PIN (backup da keypair do professor na nuvem) — PBKDF2-HMAC-SHA256
// com salt aleatório deriva a chave AES-256-GCM. O PIN nunca é armazenado:
// errar o PIN = envelope não abre. Formato do blob: JSON {salt, env}.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';

final _pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 150000,
  bits: 256,
);

Future<SessionCrypto> _cryptoDoPin(String pin, List<int> salt) async {
  final sk = await _pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
  return SessionCrypto(await sk.extractBytes());
}

/// Sela `dados` com o PIN. Retorna o blob JSON pronto pra subir.
Future<String> selarComPin(String pin, Map<String, dynamic> dados) async {
  final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final crypto = await _cryptoDoPin(pin, salt);
  return jsonEncode({
    'salt': base64Encode(salt),
    'env': await crypto.seal(dados),
  });
}

/// Abre um blob selado por [selarComPin]. Lança se o PIN estiver errado
/// (falha de autenticação do GCM) ou o blob for inválido.
Future<Map<String, dynamic>> abrirComPin(String pin, String blob) async {
  final m = jsonDecode(blob) as Map<String, dynamic>;
  final salt = base64Decode(m['salt'] as String);
  final crypto = await _cryptoDoPin(pin, salt);
  return crypto.open(m['env'] as String);
}
