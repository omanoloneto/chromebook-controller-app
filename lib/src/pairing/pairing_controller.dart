// Orquestra o servidor de controle e expõe o necessário para a UI.

import '../commands/command.dart';
import '../server/control_server.dart';
import 'pairing_payload.dart';

class PairingController {
  PairingController({this.deviceName = 'Celular do professor'});

  final String deviceName;
  final ControlServer _server = ControlServer();

  /// Texto do QR de pareamento (null até o servidor iniciar).
  String? qrPayload;

  void Function(bool connected)? onConnection;
  void Function(Ack ack)? onAck;

  String? get ip => _server.ip;
  int get port => _server.port;
  bool get isConnected => _server.isConnected;

  /// Inicia o servidor e prepara o QR.
  Future<void> start() async {
    _server.onConnection = (c) => onConnection?.call(c);
    _server.onAck = (m) {
      final a = Ack.fromMap(m);
      if (a != null) onAck?.call(a);
    };
    await _server.start();
    qrPayload = buildPairingQr(
      ip: _server.ip ?? '0.0.0.0',
      port: _server.port,
      key: _server.key,
      name: deviceName,
    );
  }

  /// Dispara o comando para abrir uma URL no Chromebook.
  void sendOpenUrl(String url, {bool newTab = true}) {
    _server.enqueueCommand(buildOpenUrl(url, newTab: newTab));
  }

  Future<void> stop() => _server.stop();
}
