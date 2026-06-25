// Conteúdo do QR de pareamento — ver docs/protocolo.md (QR v2).
// Casa com a extensão (src/pairing/qr.js): base64url( JSON ), sem padding.
//
// { v: 2, ip, port, key(base64url 32 bytes), name }

import 'dart:convert';

import '../secure/crypto.dart';

const int kPairingVersion = 2;

String _b64urlEncode(String s) =>
    base64Url.encode(utf8.encode(s)).replaceAll('=', '');

/// Monta o texto do QR (string que vai para o QrImageView).
String buildPairingQr({
  required String ip,
  required int port,
  required List<int> key,
  String name = 'Celular do professor',
}) {
  final obj = {
    'v': kPairingVersion,
    'ip': ip,
    'port': port,
    'key': SessionCrypto.keyToBase64url(key),
    'name': name,
  };
  return _b64urlEncode(jsonEncode(obj));
}
