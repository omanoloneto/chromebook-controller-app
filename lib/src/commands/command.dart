// Mensagens do protocolo (texto em claro, ANTES de cifrar) — ver docs/protocolo.md.
// A cifragem AES-GCM e os campos seq/ts são adicionados pela camada de transporte
// (control_server.dart via crypto.dart). Aqui só montamos/parseamos o conteúdo.

import 'domain_rules.dart';

const int kProtocolVersion = 1;

class MessageType {
  static const String openUrl = 'open_url';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String tabReport = 'tab_report';
  static const String closeTabs = 'close_tabs';
  static const String setRules = 'set_rules';
  static const String setWallpaper = 'set_wallpaper';
  // Reservados (futuro):
  static const String lockScreen = 'lock_screen';
  static const String unlockScreen = 'unlock_screen';
  static const String showMessage = 'show_message';
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

/// Monta o comando `close_tabs` — exatamente UM de [domain] | [url].
Map<String, dynamic> buildCloseTabs({String? domain, String? url}) {
  assert((domain == null) != (url == null), 'informe domain OU url');
  return {
    'v': kProtocolVersion,
    'type': MessageType.closeTabs,
    'id': _nextId(),
    'payload': {
      if (domain != null) 'domain': domain,
      if (url != null) 'url': url,
    },
  };
}

/// Monta o comando `set_rules` — snapshot completo; só regras `block` viajam
/// (as `alert` são avaliadas apenas no celular).
Map<String, dynamic> buildSetRules(List<DomainRule> regras, {required int rev}) {
  final block = regras
      .where((r) => r.action == RuleAction.block)
      .take(kMaxRules)
      .map((r) => {'pattern': r.pattern})
      .toList();
  return {
    'v': kProtocolVersion,
    'type': MessageType.setRules,
    'id': _nextId(),
    'payload': {'rev': rev, 'rules': block},
  };
}

/// Monta o comando `set_wallpaper` — o cliente busca a imagem em
/// `GET /wallpaper?h=<hash>` no celular.
Map<String, dynamic> buildSetWallpaper(String hash) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.setWallpaper,
    'id': _nextId(),
    'payload': {'hash': hash},
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

// ---- Relatório de abas (tab_report) -----------------------------------------
// Chega embutido no corpo do /poll (campo `report`) — ver docs/protocolo.md.

const int kMaxReportTabs = 30;
const int kMaxReportEvents = 20;

/// Uma aba aberta no Chromebook.
class TabInfo {
  TabInfo({required this.url, required this.title, required this.active});

  final String url;
  final String title;
  final bool active;

  static TabInfo? fromMap(dynamic m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url is! String || url.isEmpty) return null;
    return TabInfo(
      url: url,
      title: m['title'] as String? ?? '',
      active: m['active'] == true,
    );
  }
}

/// Um evento de navegação (URL visitada).
class NavEvent {
  NavEvent({required this.url, required this.title, required this.ts});

  final String url;
  final String title;
  final int ts; // epoch ms

  static NavEvent? fromMap(dynamic m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url is! String || url.isEmpty) return null;
    return NavEvent(
      url: url,
      title: m['title'] as String? ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Snapshot das abas + log rolante de navegação de um Chromebook.
class TabReport {
  TabReport({required this.tabs, required this.events});

  final List<TabInfo> tabs;
  final List<NavEvent> events;

  /// Tolerante: entradas malformadas são puladas; caps defensivos
  /// independentes do que o cliente enviou.
  static TabReport? fromMap(Map<String, dynamic> m) {
    if (m['type'] != MessageType.tabReport) return null;
    final tabs = <TabInfo>[];
    final raw = m['tabs'];
    if (raw is List) {
      for (final e in raw) {
        final t = TabInfo.fromMap(e);
        if (t != null) tabs.add(t);
        if (tabs.length >= kMaxReportTabs) break;
      }
    }
    final events = <NavEvent>[];
    final rawEv = m['events'];
    if (rawEv is List) {
      for (final e in rawEv) {
        final ev = NavEvent.fromMap(e);
        if (ev != null) events.add(ev);
        if (events.length >= kMaxReportEvents) break;
      }
    }
    return TabReport(tabs: tabs, events: events);
  }
}
