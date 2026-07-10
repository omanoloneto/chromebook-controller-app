// Notificações de evento (alerta/bloqueio) COM SOM — canal separado do canal
// silencioso 'servidor_aula' do foreground service.
//
// ⚠️ No Android 8+, som/importância congelam na criação do canal (1ª
// notificação). Para mudar no futuro: canal novo ('alertas_aula_v2') +
// deleteNotificationChannel do antigo.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Janela anti-spam por (tipo, pc, domínio).
const Duration kJanelaNotificacao = Duration(minutes: 2);

class NotificationService {
  NotificationService({DateTime Function()? relogio})
      : _relogio = relogio ?? DateTime.now;

  final DateTime Function() _relogio; // injetável p/ testes do throttle
  final _plugin = FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _ultimoDisparo = {};
  bool _pronto = false;

  /// Chamar 1x no main(), após ensureInitialized/Firebase.
  Future<void> init() async {
    if (_pronto) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    // O foreground service já pede POST_NOTIFICATIONS; isto é só fallback
    // (ex.: usuário negou lá e reativou depois nas configurações do app).
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (await android?.areNotificationsEnabled() == false) {
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

  Future<void> notificarAlerta({required String pc, required String dominio}) {
    return _notificar(
      tipo: 'alerta',
      pc: pc,
      dominio: dominio,
      titulo: '⚠ $dominio em $pc',
      corpo: '$pc acessou $dominio (site marcado como "Alertar").',
    );
  }

  Future<void> notificarBloqueado({required String pc, required String dominio}) {
    return _notificar(
      tipo: 'bloqueado',
      pc: pc,
      dominio: dominio,
      titulo: '🚫 Tentativa de site bloqueado',
      corpo: '$pc tentou acessar $dominio.',
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

  Future<void> _notificar({
    required String tipo,
    required String pc,
    required String dominio,
    required String titulo,
    required String corpo,
  }) async {
    final chave = '$tipo|$pc|$dominio';
    if (!deveDisparar(chave)) return;
    if (!_pronto) return;

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
    );
  }

  // Id estável por (tipo, pc, domínio): repetição SUBSTITUI o card em vez de
  // empilhar; eventos distintos empilham. >=1000 evita o id do serviço (256).
  int _idEstavel(String chave) => 1000 + (chave.hashCode & 0x7fffffff) % 100000;
}
