// Mensagens do protocolo (texto em claro, ANTES de cifrar) — ver docs/protocolo.md.
// A cifragem AES-GCM e os campos seq/ts são adicionados pela camada de transporte
// (control_server.dart via crypto.dart). Aqui só montamos/parseamos o conteúdo.

const int kProtocolVersion = 1;

class MessageType {
  static const String openUrl = 'open_url';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';
  // Reservados (futuro):
  static const String lockScreen = 'lock_screen';
  static const String unlockScreen = 'unlock_screen';
  static const String showMessage = 'show_message';
  static const String closeTabs = 'close_tabs';
  static const String focusMode = 'focus_mode';
}

int _seq = 0;
String _nextId() {
  _seq = (_seq + 1) % 1000000000;
  return 'a$_seq';
}

/// Monta o objeto do comando `open_url` (será cifrado pelo servidor).
Map<String, dynamic> buildOpenUrl(String url, {bool newTab = true, bool focus = true}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.openUrl,
    'id': _nextId(),
    'payload': {
      'url': url,
      'newTab': newTab,
      'focus': focus,
    },
  };
}

/// Representa um ACK recebido do Chromebook (já decifrado).
class Ack {
  Ack({required this.id, required this.ok, this.error});

  final String id;
  final bool ok;
  final String? error;

  static Ack? fromMap(Map<String, dynamic> m) {
    if (m['type'] != MessageType.ack) return null;
    return Ack(
      id: m['id'] as String? ?? '',
      ok: m['ok'] == true,
      error: m['error'] as String?,
    );
  }
}
