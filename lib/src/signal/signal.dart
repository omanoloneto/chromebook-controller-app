// Sinalização: codificação do conteúdo dos QR codes (ver docs/protocolo.md).
//
// Precisa casar EXATAMENTE com a extensão (src/lib/signal.js):
// v1 => payload = base64url( JSON ), sem compressão.
//
// Objeto: { v: 1, role: 'offer' | 'answer', sdp: '<sdp>', name: '<nome>' }

import 'dart:convert';

const int kSignalVersion = 1;

String _b64urlEncode(String s) {
  // base64Url do Dart usa o alfabeto url-safe (- e _); removemos o padding '='
  // para bater com a extensão (que também remove).
  return base64Url.encode(utf8.encode(s)).replaceAll('=', '');
}

String _b64urlDecode(String s) {
  final clean = s.trim();
  final pad = (4 - clean.length % 4) % 4;
  return utf8.decode(base64Url.decode(clean + ('=' * pad)));
}

String encodeSignal(Map<String, dynamic> obj) => _b64urlEncode(jsonEncode(obj));

Map<String, dynamic> decodeSignal(String text) =>
    jsonDecode(_b64urlDecode(text)) as Map<String, dynamic>;

/// Monta o payload do answer (lado celular) para virar o QR #2.
String makeAnswerSignal(String sdp, String name) => encodeSignal({
      'v': kSignalVersion,
      'role': 'answer',
      'sdp': sdp,
      'name': name,
    });

/// Dados de um QR de offer lido do Chromebook.
class OfferSignal {
  OfferSignal({required this.sdp, this.name});

  final String sdp;
  final String? name;

  /// Lê e valida o texto de um QR de offer. Lança [FormatException] se inválido.
  static OfferSignal parse(String qrText) {
    final Map<String, dynamic> m;
    try {
      m = decodeSignal(qrText);
    } catch (_) {
      throw const FormatException('qr_ilegivel');
    }
    if (m['role'] != 'offer') {
      throw const FormatException('qr_nao_e_offer');
    }
    if (m['v'] != kSignalVersion) {
      throw const FormatException('versao_incompativel');
    }
    final sdp = m['sdp'];
    if (sdp is! String || sdp.isEmpty) {
      throw const FormatException('sdp_ausente');
    }
    return OfferSignal(sdp: sdp, name: m['name'] as String?);
  }
}
