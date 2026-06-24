// Pareamento no app — lê o QR #1 (offer) e gera o QR #2 (answer).
// Ver docs/protocolo.md, seção "Pareamento".
//
// Esboço — nada implementado ainda.
// Câmera: mobile_scanner. Geração do QR: qr_flutter.

class PairingController {
  /// Lê o QR #1 (string já descomprimida) e devolve o SDP do offer.
  String parseOfferQr(/* String qrData */) {
    // TODO: descomprimir + validar { v, role: 'offer', sdp }
    throw UnimplementedError();
  }

  /// Monta o conteúdo do QR #2 a partir do SDP do answer.
  String buildAnswerQrPayload(/* String answerSdp */) {
    // TODO: montar { v, role: 'answer', sdp } e comprimir (deflate + base64url)
    throw UnimplementedError();
  }
}
