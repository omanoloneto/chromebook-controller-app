// Cliente WebRTC do app (papel "answerer").
// Ver o handshake por QR code em docs/protocolo.md.
//
// Esboço — nada implementado ainda. Usará o pacote flutter_webrtc.

class WebrtcClient {
  // Sem servidor de sinalização: ICE "non-trickle" e, em rede local,
  // host candidates costumam bastar (sem STUN/TURN).

  /// Recebe o OFFER (lido do QR #1) e gera o ANSWER (vai no QR #2).
  Future<String> createAnswer(/* String offerSdp */) async {
    // TODO: criar RTCPeerConnection
    // TODO: setRemoteDescription(offer)
    // TODO: createAnswer + setLocalDescription
    // TODO: aguardar o ICE gathering terminar
    // TODO: retornar a localDescription (answer) para virar o QR #2
    throw UnimplementedError();
  }

  /// Envia uma mensagem do protocolo (JSON em uma linha) pelo DataChannel.
  void send(/* String message */) {
    // TODO: dataChannel.send(...)
  }

  /// Callback chamado a cada mensagem recebida (ex.: ACK).
  void Function(String raw)? onMessage;

  Future<void> close() async {
    // TODO: fechar dataChannel e peerConnection.
  }
}
