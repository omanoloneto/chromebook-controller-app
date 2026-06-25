// Mensagens do protocolo do DataChannel — ver docs/protocolo.md.
// Mantenha em sincronia com a extensão (src/lib/protocol.js).

import 'dart:convert';

const int kProtocolVersion = 1;

/// Tipos de mensagem (espelham docs/protocolo.md).
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

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Monta a mensagem `open_url` (função prioritária — MVP) como JSON em uma linha.
String buildOpenUrlMessage(String url, {bool newTab = true, bool focus = true}) {
  return jsonEncode({
    'v': kProtocolVersion,
    'type': MessageType.openUrl,
    'id': _nextId(),
    'ts': _nowMs(),
    'payload': {
      'url': url,
      'newTab': newTab,
      'focus': focus,
    },
  });
}

/// Monta uma mensagem `ping` (keepalive).
String buildPingMessage() {
  return jsonEncode({
    'v': kProtocolVersion,
    'type': MessageType.ping,
    'id': _nextId(),
    'ts': _nowMs(),
  });
}

/// Representa um ACK recebido do Chromebook.
class Ack {
  Ack({required this.id, required this.ok, this.error});

  final String id;
  final bool ok;
  final String? error;

  static Ack? tryParse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['type'] != MessageType.ack) return null;
      return Ack(
        id: m['id'] as String? ?? '',
        ok: m['ok'] == true,
        error: m['error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
