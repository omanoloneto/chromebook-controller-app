// Modelos das mensagens do protocolo — ver docs/protocolo.md.
// Mantenha em sincronia com a extensão (src/lib/protocol.js).
//
// Esboço: estruturas básicas; a serialização completa será adicionada depois.

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

/// Comando para abrir uma URL no Chromebook (função prioritária — MVP).
class OpenUrlCommand {
  OpenUrlCommand({
    required this.id,
    required this.url,
    this.newTab = true,
    this.focus = true,
  });

  final String id;
  final String url;
  final bool newTab;
  final bool focus;

  /// Serializa para o formato do protocolo (JSON em uma linha).
  Map<String, dynamic> toJson() {
    return {
      'v': kProtocolVersion,
      'type': MessageType.openUrl,
      'id': id,
      // TODO: usar timestamp real ao enviar.
      'ts': 0,
      'payload': {
        'url': url,
        'newTab': newTab,
        'focus': focus,
      },
    };
  }
}
