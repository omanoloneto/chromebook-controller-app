// Registro de sessões — cada PC (Chromebook) vinculado vira uma sessão.
// Guarda a chave de sessão (AES), contadores anti-replay e a fila de comandos.

import '../secure/crypto.dart';

class PcSession {
  PcSession({
    required this.deviceId,
    required this.label,
    required this.crypto,
  });

  final String deviceId;
  String label;
  final SessionCrypto crypto;

  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  int lastClientSeq = 0; // anti-replay (cliente -> servidor)
  int serverSeq = 0; // servidor -> cliente
  final List<Map<String, dynamic>> queue = [];

  bool online(DateTime now) =>
      now.difference(lastSeen) < const Duration(seconds: 8);
}

class SessionRegistry {
  final Map<String, PcSession> _byId = {};

  /// Chamado quando a lista/estado muda (para a UI).
  void Function()? onChange;

  PcSession? byId(String deviceId) => _byId[deviceId];

  List<PcSession> get all => _byId.values.toList();

  /// Cria/atualiza a sessão de um PC ao (re)vincular.
  PcSession bind({
    required String deviceId,
    required String label,
    required List<int> sessionKey,
  }) {
    final s = PcSession(
      deviceId: deviceId,
      label: label,
      crypto: SessionCrypto(sessionKey),
    );
    _byId[deviceId] = s;
    onChange?.call();
    return s;
  }

  void touch(String deviceId) {
    final s = _byId[deviceId];
    if (s != null) {
      s.lastSeen = DateTime.now();
      onChange?.call();
    }
  }

  /// Enfileira um comando para um PC específico.
  void enqueueOne(String deviceId, Map<String, dynamic> cmd) {
    _byId[deviceId]?.queue.add(Map<String, dynamic>.from(cmd));
  }

  /// Enfileira um comando para TODOS os PCs (turma toda).
  void enqueueAll(Map<String, dynamic> cmd) {
    for (final s in _byId.values) {
      s.queue.add(Map<String, dynamic>.from(cmd));
    }
  }
}
