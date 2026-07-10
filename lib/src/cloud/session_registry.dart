// Registro de sessões — cada PC (Chromebook) pareado vira uma sessão.
// Guarda a chave de sessão (AES), guards anti-replay e o estado de
// monitoramento (abas abertas + histórico). No v4 (Firebase) não há mais fila
// nem contadores por request: comandos vão direto ao RTDB pelo transporte.

import '../commands/command.dart';
import '../secure/crypto.dart';
import 'replay_guard.dart';

/// Máximo de eventos de navegação guardados por PC (em memória).
const int kMaxHistoryPorPc = 200;

/// Janela p/ considerar um PC online (heartbeat de presença = 25s; 2 batidas
/// perdidas + folga).
const Duration kJanelaOnline = Duration(seconds: 60);

class PcSession {
  PcSession({
    required this.deviceId,
    required this.label,
    required this.crypto,
  });

  final String deviceId;
  String label;
  final SessionCrypto crypto;

  /// Última presença, em TEMPO DO SERVIDOR (o transporte converte).
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);

  // Anti-replay dos canais de entrada (PC -> professor).
  final ReplayGuard reportGuard = ReplayGuard();
  final ReplayGuard ackGuard = ReplayGuard();

  // Monitoramento (último relatório de abas recebido).
  List<TabInfo> tabs = [];
  final List<NavEvent> history = [];
  DateTime? lastReportAt;
  String? alerta; // domínio que disparou alerta (null = sem alerta)

  /// False até o 1º applyReport: o histórico que chega na abertura do app é
  /// velho e não deve gerar notificações.
  bool reportJaAplicado = false;

  TabInfo? get abaAtiva {
    for (final t in tabs) {
      if (t.active) return t;
    }
    return null;
  }

  /// `now` deve estar na MESMA base de tempo do lastSeen (servidor).
  bool online(DateTime now) => now.difference(lastSeen) < kJanelaOnline;
}

class SessionRegistry {
  final Map<String, PcSession> _byId = {};

  /// deviceId do "PC do professor": sem histórico, sem alerta, sem
  /// notificações (privacidade do professor + telão). Setado pelo controller.
  String? pcProfessorId;

  /// Chamado quando a lista/estado muda (para a UI).
  void Function()? onChange;

  /// Avalia as abas de um relatório e retorna o domínio em alerta (ou null).
  /// Injetado pelo PairingController (que conhece as regras e as liberações
  /// por PC da aula ativa — por isso recebe o deviceId).
  String? Function(String deviceId, List<TabInfo> tabs)? avaliarAlerta;

  /// Eventos de navegação INÉDITOS (dedup por ts|url), nunca do 1º report do
  /// PC. Injetado pelo controller (notificações de alerta/bloqueio).
  void Function(String deviceId, List<NavEvent> novos)? onNovosEventos;

  PcSession? byId(String deviceId) => _byId[deviceId];

  List<PcSession> get all => _byId.values.toList();

  /// Cria/atualiza a sessão de um PC (pareamento novo ou rehidratação do
  /// roster ao abrir o app). O estado de monitoramento antigo é preservado.
  PcSession bind({
    required String deviceId,
    required String label,
    required List<int> sessionKey,
  }) {
    final old = _byId[deviceId];
    final s = PcSession(
      deviceId: deviceId,
      label: label,
      crypto: SessionCrypto(sessionKey),
    );
    if (old != null) {
      s.tabs = old.tabs;
      s.history.addAll(old.history);
      s.lastReportAt = old.lastReportAt;
      s.alerta = old.alerta;
      s.lastSeen = old.lastSeen;
    }
    _byId[deviceId] = s;
    onChange?.call();
    return s;
  }

  /// Remove a sessão (PC desvinculado/esquecido).
  void remove(String deviceId) {
    if (_byId.remove(deviceId) != null) onChange?.call();
  }

  /// Registra presença vinda do heartbeat (epoch-ms DO SERVIDOR).
  void touchServerTs(String deviceId, int serverMs) {
    final s = _byId[deviceId];
    if (s != null) {
      s.lastSeen = DateTime.fromMillisecondsSinceEpoch(serverMs);
      onChange?.call();
    }
  }

  /// Aplica um relatório de abas. `reportAt` = timestamp (servidor) do nó.
  /// `events` chega como log rolante completo — dedup por (ts, url).
  void applyReport(String deviceId, TabReport r, {DateTime? reportAt}) {
    final s = _byId[deviceId];
    if (s == null) return;
    final primeiro = !s.reportJaAplicado;
    s.reportJaAplicado = true;
    s.tabs = r.tabs;
    s.lastReportAt = reportAt ?? DateTime.now();
    // PC do professor: sem histórico/alerta/notificações (abas ficam — servem
    // p/ confirmar visualmente um open_url no telão).
    if (deviceId == pcProfessorId) {
      s.alerta = null;
      s.history.clear();
      onChange?.call();
      return;
    }
    // Recalcula a cada relatório: o alerta some sozinho quando a aba fecha.
    s.alerta = avaliarAlerta?.call(deviceId, s.tabs);
    final novos = <NavEvent>[];
    if (r.events.isNotEmpty) {
      final vistos = <String>{
        for (final e in s.history) '${e.ts}|${e.url}',
      };
      for (final e in r.events) {
        if (vistos.add('${e.ts}|${e.url}')) {
          s.history.add(e);
          novos.add(e);
        }
      }
      s.history.sort((a, b) => a.ts.compareTo(b.ts));
      if (s.history.length > kMaxHistoryPorPc) {
        s.history.removeRange(0, s.history.length - kMaxHistoryPorPc);
      }
    }
    // 1º report = histórico antigo (abertura do app): nunca notifica.
    if (!primeiro && novos.isNotEmpty) {
      onNovosEventos?.call(deviceId, novos);
    }
    onChange?.call();
  }
}
