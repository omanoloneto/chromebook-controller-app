// Foreground service: ancora o processo para os listeners do Firebase (RTDB)
// continuarem vivos com a tela apagada. NENHUMA lógica roda no isolate da
// task (handler no-op); a conexão permanece no isolate principal.

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Chamar 1x no main(), antes do runApp.
void prepararServicoAula() {
  FlutterForegroundTask.initCommunicationPort();
}

Future<void> iniciarServicoAula() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'servidor_aula',
      channelName: 'Servidor da aula',
      channelDescription: 'Mantém o servidor da aula ativo com a tela apagada.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  // Android 13+: sem esta permissão a notificação some, mas o serviço roda.
  final perm = await FlutterForegroundTask.checkNotificationPermission();
  if (perm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.startService(
    notificationTitle: 'Servidor da aula ativo',
    notificationText: '0 PC(s) conectados',
    callback: startCallback,
  );
}

Future<void> atualizarNotificacaoAula(String texto) async {
  if (!await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.updateService(notificationText: texto);
}

Future<void> pararServicoAula() async {
  if (!await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.stopService();
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_AulaTaskHandler());
}

// No-op: o serviço existe só para manter o processo (e o servidor) vivos.
class _AulaTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
