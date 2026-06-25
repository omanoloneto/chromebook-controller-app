// Orquestra o servidor multi-cliente: carrega o par de chaves do professor,
// inicia o servidor e expõe a lista de PCs + envio de comandos.

import '../commands/command.dart';
import '../secure/key_store.dart';
import '../server/control_server.dart';
import '../server/session_registry.dart';

class PairingController {
  PairingController({this.deviceName = 'Professor'});

  final String deviceName;
  ControlServer? _server;

  /// Notifica a UI quando a lista de PCs muda.
  void Function()? onChange;

  Future<void> start() async {
    final teacher = await KeyStore.loadOrCreate();
    final server = ControlServer(teacher: teacher, deviceName: deviceName);
    server.registry.onChange = () => onChange?.call();
    await server.start();
    _server = server;
  }

  String? get ip => _server?.ip;
  int get port => _server?.port ?? 0;

  List<PcSession> get pcs => _server?.registry.all ?? const [];

  bool isOnline(PcSession s) => s.online(DateTime.now());

  /// Abre uma URL em TODOS os PCs (turma toda).
  void abrirEmTodos(String url) {
    _server?.registry.enqueueAll(buildOpenUrl(url));
  }

  /// Abre uma URL em um PC específico.
  void abrirEm(String deviceId, String url) {
    _server?.registry.enqueueOne(deviceId, buildOpenUrl(url));
  }

  Future<void> stop() => _server?.stop() ?? Future.value();
}
