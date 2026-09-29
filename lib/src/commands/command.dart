// Mensagens do protocolo (texto em claro, ANTES de cifrar) — ver docs/protocolo.md.
// A cifragem AES-GCM e os campos seq/ts são adicionados pela camada de transporte
// (control_server.dart via crypto.dart). Aqui só montamos/parseamos o conteúdo.

import 'domain_rules.dart';
import 'filtros.dart';

const int kProtocolVersion = 1;

class MessageType {
  static const String openUrl = 'open_url';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String tabReport = 'tab_report';
  static const String closeTabs = 'close_tabs';
  static const String closeAllTabs = 'close_all_tabs';
  static const String setRules = 'set_rules';
  static const String setWallpaper = 'set_wallpaper';
  static const String showMessage = 'show_message';
  static const String setClassView = 'set_class_view';
  static const String setUnit = 'set_unit';
  static const String captureCamera = 'capture_camera'; // app -> ext: foto da webcam
  static const String cameraSnapshot = 'camera_snapshot'; // ext -> app: foto cifrada
  static const String captureScreen = 'capture_screen'; // app -> agente Celita: tela
  static const String screenSnapshot = 'screen_snapshot'; // agente -> app: tela cifrada
  static const String liberarIas = 'liberar_ias'; // app -> agente Celita: IAs até o logout
  // Reservados (futuro):
  static const String lockScreen = 'lock_screen';
  static const String unlockScreen = 'unlock_screen';
  static const String focusMode = 'focus_mode';
}

int _seq = 0;
String _nextId() {
  _seq = (_seq + 1) % 1000000000;
  return 'a$_seq';
}

/// Id de comando para builders que vivem fora deste arquivo (class_view.dart).
String nextCommandId() => _nextId();

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

/// Monta o comando `close_all_tabs` — fecha tudo, sem filtro.
/// [closeWindows] true derruba as janelas inteiras (usado no "encerrar aula");
/// false fecha as abas deixando 1 vazia.
Map<String, dynamic> buildCloseAllTabs({bool closeWindows = false}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.closeAllTabs,
    'id': _nextId(),
    'payload': {'closeWindows': closeWindows},
  };
}

/// Monta o comando `show_message`. Sem [popup]: notificação do sistema
/// (avisos no telão, ext >= 0.4.2). Com [popup] true (ext >= 0.4.8): abre a
/// página "Mensagem do professor" em aba nova; [de] = nome do professor.
/// Extensão antiga ignora os campos extras e degrada p/ notificação.
Map<String, dynamic> buildShowMessage(
  String title,
  String body, {
  bool popup = false,
  String? de,
}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.showMessage,
    'id': _nextId(),
    'payload': {
      'title': title,
      'body': body,
      if (popup) 'popup': true,
      if (popup && de != null) 'de': de,
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

/// Monta o comando `set_rules` — snapshot completo. `rules` = bloqueios menos
/// os [liberados] deste PC; `alerts` = todas as regras "só me avisar" (a
/// liberação só afeta bloqueio). `alerts` vai sempre, mesmo vazio.
Map<String, dynamic> buildSetRules(
  List<DomainRule> regras, {
  required int rev,
  Set<String> liberados = const {},
  Filtros filtros = Filtros.padrao,
}) {
  List<Map<String, String>> padroes(bool Function(DomainRule) filtro) => regras
      .where(filtro)
      .take(kMaxRules)
      .map((r) => {'pattern': r.pattern})
      .toList();
  return {
    'v': kProtocolVersion,
    'type': MessageType.setRules,
    'id': _nextId(),
    'payload': {
      'rev': rev,
      'rules': padroes(
        (r) => r.action == RuleAction.block && !liberados.contains(r.pattern),
      ),
      'alerts': padroes((r) => r.action == RuleAction.alert),
      'filtros': filtros.toMap(),
    },
  };
}

/// Monta o comando `liberar_ias` — libera (ou volta a bloquear) as IAs só na
/// sessão aberta no PC; a liberação acaba quando a pessoa sai da conta. Só o
/// agente do Celita OS atende; sem ninguém na conta vem `sem_sessao`.
Map<String, dynamic> buildLiberarIas({required bool liberar}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.liberarIas,
    'id': _nextId(),
    'payload': {'liberar': liberar},
  };
}

/// Monta o comando `set_unit` — número da unidade editado pós-pareamento
/// (estado, não fila: sobrevive a PC offline; requer extensão >= 0.4.6).
Map<String, dynamic> buildSetUnit({required int rev, required int numero}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.setUnit,
    'id': _nextId(),
    'payload': {'rev': rev, 'numero': numero},
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

/// Monta o comando `capture_camera` — pede 1 foto da webcam do aluno. A
/// extensão responde gravando a imagem cifrada em `/devices/{id}/snapshot`
/// (ext >= 0.5.0; exige a policy `VideoCaptureAllowedUrls` no fleet).
Map<String, dynamic> buildCaptureCamera() {
  return {
    'v': kProtocolVersion,
    'type': MessageType.captureCamera,
    'id': _nextId(),
    'payload': const <String, dynamic>{},
  };
}

/// Monta o comando `capture_screen` — pede 1 captura da tela do aluno. Só o
/// agente do Celita OS (>= 0.5.0) atende; a extensão sozinha responde
/// `tipo_desconhecido`, e sem sessão de aluno aberta vem `sem_sessao`.
Map<String, dynamic> buildCaptureScreen() {
  return {
    'v': kProtocolVersion,
    'type': MessageType.captureScreen,
    'id': _nextId(),
    'payload': const <String, dynamic>{},
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
const int kMaxReportApps = 30;
const int kMaxReportAppName = 40;
const int kMaxReportAppTitle = 120;
const int kMaxReportUser = 32;

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
  NavEvent({required this.url, required this.title, required this.ts, this.bloqueio});

  final String url;
  final String title;
  final int ts; // epoch ms

  /// Motivo com que a extensão bloqueou a tentativa ('regra', 'shorts',
  /// 'reels', 'tiktok', 'ia', 'canal'); null = não foi bloqueada.
  final String? bloqueio;

  static NavEvent? fromMap(dynamic m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url is! String || url.isEmpty) return null;
    return NavEvent(
      url: url,
      title: m['title'] as String? ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      bloqueio: m['bloqueio'] is String && (m['bloqueio'] as String).isNotEmpty
          ? _corta(m['bloqueio'] as String, 20)
          : null,
    );
  }
}

/// Um programa aberto fora do navegador. Só o agente do Celita OS reporta.
class AppInfo {
  AppInfo({required this.name, required this.title});

  final String name;
  final String title;

  static AppInfo? fromMap(dynamic m) {
    if (m is! Map) return null;
    final name = m['name'];
    if (name is! String || name.isEmpty) return null;
    return AppInfo(
      name: _corta(name, kMaxReportAppName),
      title: _corta(m['title'] as String? ?? '', kMaxReportAppTitle),
    );
  }
}

String _corta(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Snapshot das abas + log rolante de navegação de um Chromebook.
class TabReport {
  TabReport({
    required this.tabs,
    required this.events,
    this.apps = const [],
    this.user,
    this.iasLiberadas = false,
  });

  final List<TabInfo> tabs;
  final List<NavEvent> events;

  /// Programas abertos fora do navegador e conta logada: só o agente do
  /// Celita OS manda (a extensão omite; lista vazia e null são o normal).
  final List<AppInfo> apps;
  final String? user;

  /// As IAs estão liberadas na sessão aberta no PC (comando liberar_ias).
  final bool iasLiberadas;

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
    final apps = <AppInfo>[];
    final rawApps = m['apps'];
    if (rawApps is List) {
      for (final e in rawApps) {
        final a = AppInfo.fromMap(e);
        if (a != null) apps.add(a);
        if (apps.length >= kMaxReportApps) break;
      }
    }
    final rawUser = m['user'];
    final user = rawUser is String && rawUser.isNotEmpty
        ? _corta(rawUser, kMaxReportUser)
        : null;
    return TabReport(
      tabs: tabs,
      events: events,
      apps: apps,
      user: user,
      iasLiberadas: m['iasLiberadas'] == true,
    );
  }
}
