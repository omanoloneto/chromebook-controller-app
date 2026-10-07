// Mensagens do protocolo (texto em claro, ANTES de cifrar) — ver docs/protocolo.md.
// A cifragem AES-GCM e os campos seq/ts são adicionados pela camada de transporte
// (control_server.dart via crypto.dart). Aqui só montamos/parseamos o conteúdo.

import 'dart:convert';
import 'dart:typed_data';

import '../util/ids.dart';
import 'domain_rules.dart';
import 'filtros.dart';
import 'liberacao.dart';

const int kProtocolVersion = 1;

// ---- Constantes dos recursos de turma (SPEC-turma §1.6; mesmos nomes nos
// quatro códigos: agente, GTK, extensão e app) -------------------------------

const int kUpMaxEnvelope = 4096; // rules: cada filho de up/ < 4096 caracteres
const int kMaxChatTexto = 500; // code points
const int kMaxChatDe = 60;
const int kMaxPedidoSite = 100;
const int kMaxPedidoUrl = 500;
const int kMaxPedidoMotivo = 200;
const int kMaxTravaTexto = 200;
const int kMaxProvaInicio = 2048;
const int kUpMaxEntradas = 20;
const Duration kUpIdadeMaxPc = Duration(hours: 2);
const Duration kUpIdadeMaxProfessor = Duration(hours: 12);
const Duration kUpJanelaPassado = Duration(hours: 12);
const Duration kUpJanelaFuturo = Duration(seconds: 120);
const Duration kTravaAte = Duration(minutes: 20);
const Duration kTravaTeto = Duration(hours: 2);
const Duration kProvaAte = Duration(hours: 2);
const Duration kProvaTeto = Duration(hours: 4);
const Duration kRenovacao = Duration(minutes: 5);
const Duration kMonitorRenova = Duration(seconds: 10);
const Duration kMonitorAte = Duration(seconds: 30);
const Duration kMonitorTeto = Duration(seconds: 45);
const Duration kMonitorJanelaTs = Duration(seconds: 120);
const int kThumbCapLido = 256 * 1024;
const Duration kEntregaTimeout = Duration(seconds: 25);
const int kChatHistoricoPc = 100;
const int kChatHistoricoThread = 200;
const Duration kMaoVisivel = Duration(minutes: 10);
const Duration kPedidoSemResposta = Duration(minutes: 10);
const Duration kRecargaEspera = Duration(seconds: 10);
const int kMaxAplicadoAcks = 20;

/// Corta [s] em [max] code points (os caps do protocolo contam code points,
/// não unidades UTF-16 — emoji não pode ser partido ao meio).
String cortarCodePoints(String s, int max) {
  final runas = s.runes;
  if (runas.length <= max) return s;
  return String.fromCharCodes(runas.take(max));
}

int contarCodePoints(String s) => s.runes.length;

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
  static const String atualizar = 'atualizar'; // app -> agente Celita: atualizar o sistema agora
  static const String enviarMidia = 'enviar_midia'; // app -> agente Celita: subir uma foto/vídeo da Câmera
  static const String apagarMidia = 'apagar_midia'; // app -> agente Celita: apagar fotos/vídeos do PC
  // Recursos de turma (app >= 0.20.0, ext >= 0.7.0, Celita >= 0.13.0):
  static const String chatMessage = 'chat_message'; // cmd: chat professor -> aluno
  static const String unblockResult = 'unblock_result'; // cmd: resposta a um pedido
  static const String setLock = 'set_lock'; // state/lock: "Olhos em mim"
  static const String setExam = 'set_exam'; // state/exam: modo prova
  static const String setMonitor = 'set_monitor'; // state/monitor: grade ao vivo
  static const String thumbSnapshot = 'thumb_snapshot'; // /thumbs/{id}: miniatura
}

/// Tipos do canal `up/` (aluno -> professor).
class UpType {
  static const String chat = 'chat';
  static const String unblockRequest = 'unblock_request';
  static const String raiseHand = 'raise_hand';

  static const Set<String> todos = {chat, unblockRequest, raiseHand};
}

/// Comandos que só o agente do Celita OS atende (o "tipo_desconhecido" deles
/// num Chromebook vira "Isso só funciona nos computadores com Celita OS.").
const Set<String> kComandosSoCelita = {
  MessageType.captureScreen,
  MessageType.liberarIas,
  MessageType.atualizar,
};

String _nextId() => novoId();

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
/// false fecha as abas deixando 1 vazia. [fimDeAula] (só no "Encerrar aula")
/// faz o cliente novo limpar chat, pedidos e contadores; o antigo ignora.
Map<String, dynamic> buildCloseAllTabs({
  bool closeWindows = false,
  bool fimDeAula = false,
}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.closeAllTabs,
    'id': _nextId(),
    'payload': {
      'closeWindows': closeWindows,
      if (fimDeAula) 'fimDeAula': true,
    },
  };
}

/// Monta o comando `chat_message` — mensagem do professor para a janela de
/// chat do aluno. [mid] identifica a mensagem (o balão); o `id` do comando é
/// outro (o do ack). Texto e nome cortados nos caps do protocolo.
Map<String, dynamic> buildChatMessage({
  required String texto,
  required String de,
  required String mid,
}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.chatMessage,
    'id': _nextId(),
    'payload': {
      'texto': cortarCodePoints(texto.trim(), kMaxChatTexto),
      'de': cortarCodePoints(de.trim(), kMaxChatDe),
      'mid': mid,
    },
  };
}

/// Monta o comando `unblock_result` — resposta a um pedido de liberação.
/// Aprovado leva o `rev` das regras ([rulesRev]) ou da prova ([examRev]) que
/// o PC precisa ter aplicado antes de reabrir a aba.
Map<String, dynamic> buildUnblockResult({
  required String mid,
  required String site,
  required bool approved,
  String? motivo,
  int? rulesRev,
  int? examRev,
}) {
  final m = motivo == null ? '' : cortarCodePoints(motivo.trim(), kMaxPedidoMotivo);
  return {
    'v': kProtocolVersion,
    'type': MessageType.unblockResult,
    'id': _nextId(),
    'payload': {
      'mid': mid,
      'site': site,
      'approved': approved,
      if (!approved && m.isNotEmpty) 'motivo': m,
      if (approved && rulesRev != null) 'rulesRev': rulesRev,
      if (approved && examRev != null) 'examRev': examRev,
    },
  };
}

/// Texto padrão da trava (o primeiro preset de "Olhos em mim").
const String kTravaTextoPadrao = 'Olhos no professor';

/// Monta o comando de estado `set_lock` ("Olhos em mim") para `state/lock`.
/// [ate] = prazo no relógio do SERVIDOR; o PC converte para o próprio relógio.
Map<String, dynamic> buildSetLock({
  required int rev,
  required bool on,
  required String texto,
  required bool mute,
  required int ate,
}) {
  var t = cortarCodePoints(texto.trim(), kMaxTravaTexto);
  if (t.isEmpty) t = kTravaTextoPadrao;
  return {
    'v': kProtocolVersion,
    'type': MessageType.setLock,
    'id': _nextId(),
    'payload': {'rev': rev, 'on': on, 'texto': t, 'mute': mute, 'ate': ate},
  };
}

/// Monta o comando de estado `set_exam` (modo prova) para `state/exam`.
/// [allow] = padrões permitidos (normalizados como as regras, sem repetição,
/// sem sufixo público, ≤ 1000); [inicio] = página inicial da escola (só http/https ≤ 2048).
Map<String, dynamic> buildSetExam({
  required int rev,
  required bool on,
  required Iterable<String> allow,
  String? inicio,
  required int ate,
}) {
  final padroes = <String>[];
  for (final p in allow) {
    final n = normalizarPadrao(p);
    // Sufixo público/domínio de topo liberaria meia internet na prova.
    if (n.isEmpty || padraoAmploDemais(n) || padroes.contains(n)) continue;
    padroes.add(n);
    if (padroes.length >= kMaxRules) break;
  }
  final ini = inicio?.trim() ?? '';
  final iniValido = ini.isNotEmpty &&
      ini.length <= kMaxProvaInicio &&
      (ini.startsWith('https://') || ini.startsWith('http://'));
  return {
    'v': kProtocolVersion,
    'type': MessageType.setExam,
    'id': _nextId(),
    'payload': {
      'rev': rev,
      'on': on,
      'allow': [for (final p in padroes) {'pattern': p}],
      if (iniValido) 'inicio': ini,
      'ate': ate,
    },
  };
}

/// Monta o comando de estado `set_monitor` (grade ao vivo) para
/// `state/monitor`. O professor renova a cada 10 s com `ate = agora + 30 s`.
Map<String, dynamic> buildSetMonitor({required int rev, required int ate}) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.setMonitor,
    'id': _nextId(),
    'payload': {'rev': rev, 'ate': ate},
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

/// Monta o comando `atualizar` — o PC roda na hora a mesma verificação do
/// "Atualizar agora" da Central do Celita. Só o agente do Celita OS atende.
Map<String, dynamic> buildAtualizar() {
  return {
    'v': kProtocolVersion,
    'type': MessageType.atualizar,
    'id': _nextId(),
    'payload': const <String, dynamic>{},
  };
}

/// Monta o comando `enviar_midia` — o PC sobe uma foto ou vídeo da Câmera em
/// partes cifradas e informa o progresso em /envios. Só o agente do Celita.
Map<String, dynamic> buildEnviarMidia(String mid) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.enviarMidia,
    'id': _nextId(),
    'payload': {'mid': mid},
  };
}

/// Monta o comando `apagar_midia` — apaga do PC as fotos e vídeos da Câmera.
Map<String, dynamic> buildApagarMidia(List<String> mids) {
  return {
    'v': kProtocolVersion,
    'type': MessageType.apagarMidia,
    'id': _nextId(),
    'payload': {'mids': mids},
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

// ---- Canal up/ (aluno -> professor) -----------------------------------------
// Texto em claro {sid, seq, ts, v:1, type, mid, payload} — ver
// docs/protocolo.md "### `up`". Quem envia corta nos caps; o professor
// revalida: tipo/mid/site inválido = item descartado calado.

final RegExp _formatoMid = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Um item do `up/` já decifrado e validado.
class UpMessage {
  UpMessage._({
    required this.type,
    required this.mid,
    required this.sid,
    required this.seq,
    required this.ts,
    this.texto,
    this.site,
    this.url,
    this.motivo,
    this.bloqueio,
  });

  final String type; // UpType.*
  final String mid;
  final int sid;
  final int seq;
  final int ts; // relógio do PC (só para a janela do guard e exibição)

  /// `chat`: texto 1..500 code points.
  final String? texto;

  /// `unblock_request`: host validado, URL ≤ 500, motivo ≤ 200 e o tipo do
  /// bloqueio ('regra' | 'prova').
  final String? site;
  final String? url;
  final String? motivo;
  final String? bloqueio;

  static UpMessage? fromMap(Map<String, dynamic> m) {
    final type = m['type'];
    final mid = m['mid'];
    if (type is! String || !UpType.todos.contains(type)) return null;
    if (mid is! String || !_formatoMid.hasMatch(mid)) return null;
    final sid = (m['sid'] as num?)?.toInt();
    final seq = (m['seq'] as num?)?.toInt();
    final ts = (m['ts'] as num?)?.toInt();
    if (sid == null || seq == null || ts == null) return null;
    final payload = m['payload'];
    final p = payload is Map ? payload : const <String, dynamic>{};
    switch (type) {
      case UpType.chat:
        final t = p['texto'];
        if (t is! String) return null;
        final texto = cortarCodePoints(t.trim(), kMaxChatTexto);
        if (texto.isEmpty) return null;
        return UpMessage._(type: type, mid: mid, sid: sid, seq: seq, ts: ts, texto: texto);
      case UpType.unblockRequest:
        final site = p['site'];
        if (site is! String || !siteValido(site)) return null;
        final rawUrl = p['url'];
        final url = rawUrl is String ? rawUrl.trim() : '';
        if (url.length > kMaxPedidoUrl || !urlDoSite(url, site)) return null;
        final rawMotivo = p['motivo'];
        final motivo = rawMotivo is String
            ? cortarCodePoints(rawMotivo.trim(), kMaxPedidoMotivo)
            : '';
        final bloqueio = p['bloqueio'] == 'prova' ? 'prova' : 'regra';
        return UpMessage._(
          type: type,
          mid: mid,
          sid: sid,
          seq: seq,
          ts: ts,
          site: site,
          url: url,
          motivo: motivo,
          bloqueio: bloqueio,
        );
      default: // raise_hand: payload vazio
        return UpMessage._(type: type, mid: mid, sid: sid, seq: seq, ts: ts);
    }
  }
}

// ---- Confirmação positiva (tab_report.aplicado) ------------------------------

/// Estado de trava ou prova que o PC REALMENTE aplicou.
class EstadoAplicado {
  const EstadoAplicado({required this.rev, required this.on, this.erro});

  final int rev;
  final bool on;

  /// 'sem_sessao' (Celita sem ninguém logado: armado) ou 'navegador_antigo'
  /// (Celita com a extensão do navegador < 0.7.0); null = aplicado.
  final String? erro;

  static EstadoAplicado? fromMap(dynamic m) {
    if (m is! Map) return null;
    final rev = m['rev'];
    if (rev is! num) return null;
    final erro = m['erro'];
    return EstadoAplicado(
      rev: rev.toInt(),
      on: m['on'] == true,
      erro: erro is String && erro.isNotEmpty ? _corta(erro, 40) : null,
    );
  }
}

/// Um dos últimos acks que o PC repete no relatório.
class AckAplicado {
  const AckAplicado({required this.id, required this.ok, this.error});

  final String id;
  final bool ok;
  final String? error;
}

/// `aplicado` do tab_report (ext >= 0.7.0, Celita >= 0.13.0): o professor só
/// afirma "recebeu/travado/em prova ✓" por ack ou por isto.
class Aplicado {
  const Aplicado({this.trava, this.prova, this.acks = const []});

  final EstadoAplicado? trava;
  final EstadoAplicado? prova;
  final List<AckAplicado> acks;

  static Aplicado? fromMap(dynamic m) {
    if (m is! Map) return null;
    final acks = <AckAplicado>[];
    final raw = m['acks'];
    if (raw is List) {
      for (final a in raw) {
        if (acks.length >= kMaxAplicadoAcks) break;
        if (a is! Map) continue;
        final id = a['id'];
        if (id is! String || id.isEmpty || id.length > 32) continue;
        final error = a['error'];
        acks.add(
          AckAplicado(
            id: id,
            ok: a['ok'] == true,
            error: error is String && error.isNotEmpty ? _corta(error, 40) : null,
          ),
        );
      }
    }
    return Aplicado(
      trava: EstadoAplicado.fromMap(m['trava']),
      prova: EstadoAplicado.fromMap(m['prova']),
      acks: acks,
    );
  }
}

// ---- Estado vigente lido de state/lock e state/exam ---------------------------
// O app relê o que ele (ou outro professor da escola, mesma chave) gravou: é
// assim que a tela sabe quem está travado depois de reiniciar.

class EstadoTrava {
  const EstadoTrava({
    required this.rev,
    required this.on,
    required this.texto,
    required this.mute,
    required this.ate,
  });

  final int rev;
  final bool on;
  final String texto;
  final bool mute;
  final int ate; // relógio do servidor

  /// [cmd] = comando `set_lock` decifrado (com `payload`).
  static EstadoTrava? fromCommand(Map<String, dynamic> cmd) {
    if (cmd['type'] != MessageType.setLock) return null;
    final p = cmd['payload'];
    if (p is! Map) return null;
    final rev = p['rev'], ate = p['ate'];
    if (rev is! num || ate is! num) return null;
    final texto = p['texto'];
    return EstadoTrava(
      rev: rev.toInt(),
      on: p['on'] == true,
      texto: texto is String ? cortarCodePoints(texto, kMaxTravaTexto) : '',
      mute: p['mute'] == true,
      ate: ate.toInt(),
    );
  }

  /// Ligada e dentro do prazo (o PC destrava sozinho depois de [ate]).
  bool vigente(int agoraServidorMs) => on && agoraServidorMs < ate;
}

class EstadoProva {
  const EstadoProva({
    required this.rev,
    required this.on,
    required this.allow,
    required this.ate,
    this.inicio,
  });

  final int rev;
  final bool on;
  final List<String> allow;
  final String? inicio;
  final int ate;

  static EstadoProva? fromCommand(Map<String, dynamic> cmd) {
    if (cmd['type'] != MessageType.setExam) return null;
    final p = cmd['payload'];
    if (p is! Map) return null;
    final rev = p['rev'], ate = p['ate'];
    if (rev is! num || ate is! num) return null;
    final allow = <String>[];
    final raw = p['allow'];
    if (raw is List) {
      for (final a in raw) {
        if (a is Map && a['pattern'] is String) allow.add(a['pattern'] as String);
        if (allow.length >= kMaxRules) break;
      }
    }
    final inicio = p['inicio'];
    return EstadoProva(
      rev: rev.toInt(),
      on: p['on'] == true,
      allow: allow,
      inicio: inicio is String ? inicio : null,
      ate: ate.toInt(),
    );
  }

  bool vigente(int agoraServidorMs) => on && agoraServidorMs < ate;
}

// ---- Miniatura da grade (/thumbs/{id}) ---------------------------------------

/// `thumb_snapshot` decifrado. [jpeg] null = marcador ([motivo] diz por quê:
/// 'sem_sessao', 'sem_permissao', 'aba_protegida' ou 'falhou').
class Miniatura {
  const Miniatura({
    required this.ts,
    this.jpeg,
    this.w = 0,
    this.h = 0,
    this.motivo,
  });

  final Uint8List? jpeg;
  final int w;
  final int h;
  final String? motivo;

  /// `ts` do nó (relógio do servidor) — idade e "carregando" da grade.
  final int ts;

  static Miniatura? fromMap(Map<String, dynamic> m, {required int ts}) {
    if (m['type'] != MessageType.thumbSnapshot) return null;
    final b64 = m['jpegB64'];
    Uint8List? jpeg;
    if (b64 is String && b64.isNotEmpty) {
      try {
        jpeg = base64Decode(b64);
      } catch (_) {
        return null;
      }
    }
    final motivo = m['motivo'];
    return Miniatura(
      ts: ts,
      jpeg: jpeg,
      w: (m['w'] as num?)?.toInt() ?? 0,
      h: (m['h'] as num?)?.toInt() ?? 0,
      motivo: jpeg == null
          ? (motivo is String && motivo.isNotEmpty ? _corta(motivo, 20) : 'falhou')
          : null,
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
    this.aplicado,
  });

  final List<TabInfo> tabs;
  final List<NavEvent> events;

  /// Programas abertos fora do navegador e conta logada: só o agente do
  /// Celita OS manda (a extensão omite; lista vazia e null são o normal).
  final List<AppInfo> apps;
  final String? user;

  /// As IAs estão liberadas na sessão aberta no PC (comando liberar_ias).
  final bool iasLiberadas;

  /// Confirmação positiva (ext >= 0.7.0, Celita >= 0.13.0); null = cliente
  /// antigo.
  final Aplicado? aplicado;

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
      aplicado: Aplicado.fromMap(m['aplicado']),
    );
  }
}
