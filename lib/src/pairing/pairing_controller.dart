// Pareamento no app — junta a leitura do QR (offer), a geração do answer e o
// envio de comandos. Ver docs/protocolo.md.

import '../commands/command.dart';
import '../signal/signal.dart';
import '../webrtc/webrtc_client.dart';

class PairingController {
  PairingController({this.deviceName = 'Celular do professor'});

  final String deviceName;
  final WebrtcAnswerer _client = WebrtcAnswerer();

  /// Último answer gerado (texto que vira o QR #2).
  String? answerPayload;

  set onState(void Function(ConnState state) cb) => _client.onState = cb;
  set onMessage(void Function(String raw) cb) => _client.onMessage = cb;

  bool get isConnected => _client.isConnected;

  /// Recebe o texto do QR #1 (offer), gera o answer e devolve o payload do QR #2.
  Future<String> handleScannedOffer(String qrText) async {
    final offer = OfferSignal.parse(qrText); // valida role/versão/sdp
    final answerSdp = await _client.answerFromOffer(offer.sdp);
    answerPayload = makeAnswerSignal(answerSdp, deviceName);
    return answerPayload!;
  }

  /// Envia o comando para abrir uma URL no Chromebook.
  Future<void> sendOpenUrl(String url, {bool newTab = true}) async {
    await _client.send(buildOpenUrlMessage(url, newTab: newTab));
  }

  Future<void> dispose() => _client.close();
}
