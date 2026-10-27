// Notificações de evento (alerta/bloqueio) COM SOM — canal separado do canal
// silencioso 'servidor_aula' do foreground service. Recados dos alunos (chat,
// pedido de liberação, mão levantada) vão num canal próprio, privado na tela
// de bloqueio (texto de aluno é dado de menor).
//
// ⚠️ No Android 8+, som/importância congelam na criação do canal (1ª
// notificação). Para mudar no futuro: canal novo ('alertas_aula_v2') +
// deleteNotificationChannel do antigo.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Janela anti-spam por (tipo, deviceId, domínio).
const Duration kJanelaNotificacao = Duration(minutes: 2);

/// Destino do toque numa notificação: o PC, o momento do evento e o tipo do
/// recado ([k] = 'chat' | 'pedido' | 'mao'; null = alerta de site, o payload
/// antigo `{d, ts}`). Chat e mão abrem a conversa; pedido abre Recados.
typedef ToqueNotificacao = ({String deviceId, int ts, String? k});

/// Tipos de recado aceitos no payload (`k`).
const Set<String> kTiposDeRecado = {'chat', 'pedido', 'mao'};

class NotificationService {
  NotificationService({DateTime Function()? relogio})
      : _relogio = relogio ?? DateTime.now;

  final DateTime Function() _relogio; // injetável p/ testes do throttle
  final _plugin = FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _ultimoDisparo = {};
  final StreamController<ToqueNotificacao> _toques =
      StreamController.broadcast();
  ToqueNotificacao? _abertura;
  bool _pronto = false;

  /// Toques em notificações com o app aberto ou em segundo plano.
  Stream<ToqueNotificacao> get toques => _toques.stream;

  /// Notificação que abriu o app do zero (lida uma vez só).
  ToqueNotificacao? consumirAbertura() {
    final t = _abertura;
    _abertura = null;
    return t;
  }

  static String montarPayload(String deviceId, int ts, {String? k}) =>
      jsonEncode({'d': deviceId, 'ts': ts, if (k != null) 'k': k});

  /// null = payload ausente ou de outro formato. `k` desconhecido = null
  /// (vira o toque de alerta, que abre a tela do PC).
  static ToqueNotificacao? lerPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload);
      if (m is! Map) return null;
      final d = m['d'];
      final ts = m['ts'];
      if (d is! String || d.isEmpty || ts is! num) return null;
      final k = m['k'];
      return (
        deviceId: d,
        ts: ts.toInt(),
        k: k is String && kTiposDeRecado.contains(k) ? k : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Chamar 1x no main(), após ensureInitialized/Firebase. No isolate do
  /// push ([pedirPermissao] = false) não há tela para pedir permissão.
  Future<void> init({bool pedirPermissao = true}) async {
    if (_pronto) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final t = lerPayload(r.payload);
        if (t != null) _toques.add(t);
      },
    );
    final lancamento = await _plugin.getNotificationAppLaunchDetails();
    if (lancamento?.didNotificationLaunchApp ?? false) {
      _abertura = lerPayload(lancamento!.notificationResponse?.payload);
    }
    // O foreground service já pede POST_NOTIFICATIONS; isto é só fallback
    // (ex.: usuário negou lá e reativou depois nas configurações do app).
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (pedirPermissao && await android?.areNotificationsEnabled() == false) {
      await android?.requestNotificationsPermission();
    }
    _pronto = true;
  }

  /// Permissão de notificação concedida? (null = plataforma sem suporte/teste)
  Future<bool?> habilitadasNoSistema() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.areNotificationsEnabled();
  }

  /// Retorna true se passou pelo throttle e disparou (o controller usa o
  /// retorno para também avisar o PC do professor).
  Future<bool> notificarAlerta({
    required String deviceId,
    required int ts,
    required String pc,
    required String dominio,
  }) {
    return _notificar(
      tipo: 'alerta',
      deviceId: deviceId,
      ts: ts,
      dominio: dominio,
      titulo: '⚠ $dominio em $pc',
      corpo: '$pc acessou $dominio (site marcado como "Só me avisar").',
    );
  }

  Future<bool> notificarBloqueado({
    required String deviceId,
    required int ts,
    required String pc,
    required String dominio,
  }) {
    return _notificar(
      tipo: 'bloqueado',
      deviceId: deviceId,
      ts: ts,
      dominio: dominio,
      titulo: '🚫 Tentativa de site bloqueado',
      corpo: '$pc tentou acessar $dominio.',
    );
  }

  /// Um card por PC e tipo de recado.
  static String chaveDoRecado(String k, String deviceId) => 'recado|$k|$deviceId';

  /// Id do card, fixo por PC e tipo: o Android junta o toque dos cards de
  /// mesmo id, e cada card tem de abrir o seu PC. Faixa só dos recados, longe
  /// dos alertas ([_idEstavel]) e do serviço (256).
  static int idDoRecado(String k, String deviceId) =>
      0x40000000 | (chaveDoRecado(k, deviceId).hashCode & 0x3fffffff);

  /// Tag do card: a chave, o ts (push id) do recado que tocou e a hora local
  /// do toque. Push e app aberto são isolates diferentes: é pela barra que um
  /// sabe que o outro já tocou.
  static String tagDoRecado(String k, String deviceId, {required int ts, required int tocouEm}) =>
      '${chaveDoRecado(k, deviceId)}|$ts|$tocouEm';

  /// Card do recado [ts], pelos tags dos cards na barra e pela hora local
  /// [agoraMs]. Toca no máximo uma vez a cada [kJanelaNotificacao] por PC e
  /// tipo, e o card mostra o recado mais novo; o mesmo recado pelos dois
  /// caminhos toca uma vez; card tirado da barra toca de novo. [tag] nulo =
  /// recado mais velho que o que tocou (fica o card na barra); [saem] = cards
  /// do mesmo PC e tipo que saem.
  static ({String? tag, bool toca, List<String> saem}) cardDoRecado({
    required String k,
    required String deviceId,
    required int ts,
    required int agoraMs,
    required Iterable<String?> tagsAtivos,
  }) {
    final prefixo = '${chaveDoRecado(k, deviceId)}|';
    final ativos = <({String tag, int ts, int tocouEm})>[];
    for (final tag in tagsAtivos) {
      if (tag == null || !tag.startsWith(prefixo)) continue;
      final partes = tag.substring(prefixo.length).split('|');
      if (partes.length != 2) continue;
      final t = int.tryParse(partes[0]), em = int.tryParse(partes[1]);
      if (t != null && em != null) ativos.add((tag: tag, ts: t, tocouEm: em));
    }
    final novo = tagDoRecado(k, deviceId, ts: ts, tocouEm: agoraMs);
    if (ativos.isEmpty) return (tag: novo, toca: true, saem: const []);
    ativos.sort((a, b) => b.ts.compareTo(a.ts));
    final atual = ativos.first;
    final duplicados = [for (final a in ativos.skip(1)) a.tag];
    if (ts < atual.ts) return (tag: null, toca: false, saem: duplicados);
    if (ts > atual.ts && agoraMs - atual.tocouEm >= kJanelaNotificacao.inMilliseconds) {
      return (tag: novo, toca: true, saem: [for (final a in ativos) a.tag]);
    }
    return (tag: atual.tag, toca: false, saem: duplicados);
  }

  // Em série por PC e tipo (todas as instâncias do isolate): chamadas sem
  // await leriam a mesma foto da barra e tocariam todas.
  static final Map<String, Future<void>> _filasDeRecado = {};

  /// Recado de aluno: [k] = 'chat' (título = nome, corpo = texto), 'pedido'
  /// ("Pedido de liberação" / "{nome}: {site}") ou 'mao' ("Mão levantada" /
  /// "{nome}"). O card de cada PC e tipo mostra o recado mais novo e toca no
  /// máximo uma vez a cada 2 min ([cardDoRecado]).
  Future<bool> notificarRecado({
    required String k,
    required String deviceId,
    required int ts,
    required String titulo,
    required String corpo,
  }) async {
    if (!kTiposDeRecado.contains(k)) return false;
    if (!_pronto) return true;
    final chave = chaveDoRecado(k, deviceId);
    final vez = (_filasDeRecado[chave] ?? Future<void>.value())
        .then((_) => _mostrarRecado(k: k, deviceId: deviceId, ts: ts, titulo: titulo, corpo: corpo))
        .catchError((Object e) => debugPrint('[CdA] recado: $e'));
    _filasDeRecado[chave] = vez;
    await vez;
    return true;
  }

  Future<void> _mostrarRecado({
    required String k,
    required String deviceId,
    required int ts,
    required String titulo,
    required String corpo,
  }) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var ativas = const <ActiveNotification>[];
    try {
      ativas = await android?.getActiveNotifications() ?? ativas;
    } catch (e) {
      debugPrint('[CdA] notificações ativas: $e'); // o recado aparece mesmo assim
    }
    final card = cardDoRecado(
      k: k,
      deviceId: deviceId,
      ts: ts,
      agoraMs: _relogio().millisecondsSinceEpoch,
      tagsAtivos: [for (final a in ativas) a.tag],
    );
    for (final a in ativas) {
      if (a.id != null && card.saem.contains(a.tag)) {
        await android?.cancel(id: a.id!, tag: a.tag);
      }
    }
    final tag = card.tag;
    if (tag == null) return;
    // Toque = tag novo (notificação nova); o mesmo tag só atualiza o card,
    // calado pelo onlyAlertOnce.
    await _plugin.show(
      id: idDoRecado(k, deviceId),
      title: titulo,
      body: corpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'recados_alunos',
          'Recados dos alunos',
          channelDescription:
              'Mensagens, pedidos de liberação e mãos levantadas dos alunos.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          // Tela de bloqueio: o Android esconde o texto (dado de aluno).
          visibility: NotificationVisibility.private,
          onlyAlertOnce: true,
          tag: tag,
        ),
      ),
      payload: montarPayload(deviceId, ts, k: k),
    );
  }

  /// Visível para teste: aplica o throttle e registra o disparo.
  /// Retorna false se ainda está dentro da janela anti-spam.
  bool deveDisparar(String chave) {
    final agora = _relogio();
    final ultimo = _ultimoDisparo[chave];
    if (ultimo != null && agora.difference(ultimo) < kJanelaNotificacao) {
      return false;
    }
    _ultimoDisparo[chave] = agora;
    // Poda: o mapa não cresce sem limite numa aula longa.
    if (_ultimoDisparo.length > 500) {
      final corte = agora.subtract(kJanelaNotificacao);
      _ultimoDisparo.removeWhere((_, t) => t.isBefore(corte));
    }
    return true;
  }

  Future<bool> _notificar({
    required String tipo,
    required String deviceId,
    required int ts,
    required String dominio,
    required String titulo,
    required String corpo,
  }) async {
    // Pelo deviceId, não pelo nome: renomear/escolher aluno não fura o
    // throttle nem empilha um card novo.
    final chave = '$tipo|$deviceId|$dominio';
    if (!deveDisparar(chave)) return false;
    if (!_pronto) return true; // decisão vale (telão notifica mesmo sem plugin)

    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        'alertas_aula',
        'Alertas da aula',
        channelDescription:
            'Avisos sonoros quando um PC abre site em alerta ou tenta um '
            'site bloqueado.',
        importance: Importance.high, // heads-up + som padrão do sistema
        priority: Priority.high,
        category: AndroidNotificationCategory.event,
      ),
    );
    await _plugin.show(
      id: _idEstavel(chave),
      title: titulo,
      body: corpo,
      notificationDetails: detalhes,
      payload: montarPayload(deviceId, ts),
    );
    return true;
  }

  // Id estável por (tipo, deviceId, domínio): repetição SUBSTITUI o card em vez de
  // empilhar; eventos distintos empilham. >=1000 evita o id do serviço (256).
  int _idEstavel(String chave) => 1000 + (chave.hashCode & 0x7fffffff) % 100000;
}
