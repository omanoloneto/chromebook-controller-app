// Payload do QR de pareamento (v4) — gerado pela extensão
// (src/lib/protocol.js, makeQrPayload) e escaneado pelo app.
// Formato: {"v":4,"id":"<deviceId>","pub":"<b64url>","tok":"<b64url>","label":"..."}

import 'dart:convert';

class QrPairPayload {
  QrPairPayload({
    required this.deviceId,
    required this.pub,
    required this.token,
    required this.label,
  });

  final String deviceId;
  final String pub; // devicePub X25519 (base64url)
  final String token; // token one-time (valida o bind nas rules)
  final String label;

  /// Retorna null se o conteúdo não é um QR de pareamento v4 válido.
  static QrPairPayload? parse(String raw) {
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) return null;
      m = decoded;
    } catch (_) {
      return null;
    }
    if (m['v'] != 4) return null;
    final id = m['id'];
    final pub = m['pub'];
    final tok = m['tok'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (pub is! String || pub.isEmpty || pub.length > 64) return null;
    if (tok is! String || tok.isEmpty || tok.length > 64) return null;
    final label = m['label'];
    return QrPairPayload(
      deviceId: id,
      pub: pub,
      token: tok,
      label: label is String && label.isNotEmpty ? label : 'Chromebook',
    );
  }
}
