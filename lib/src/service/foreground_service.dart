// Serviço em primeiro plano: segura o processo (wake lock e Wi-Fi) e, no
// isolate próprio, faz o que tem de seguir com o app fechado — conta os PCs
// ligados na notificação fixa (o único que escreve esse texto), na escola
// renova a reserva dos PCs da aula aberta (com ele de pé, o app não renova) e
// mantém o token do push em /fcm. Sobe também no boot e depois de atualizar o
// app. Nenhuma chave de cifra é carregada aqui.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../firebase_options.dart';
import '../cloud/aula_locks.dart';
import '../commands/command.dart';
import '../pairing/class_session_store.dart';
import '../pairing/prefs_store.dart';
import 'presenca_dos_pcs.dart';
import 'push_service.dart';

/// Chamar 1x no main(), antes do runApp.
void prepararServicoAula() {
  FlutterForegroundTask.initCommunicationPort();
}

ForegroundTaskOptions _opcoes() => ForegroundTaskOptions(
      // Recontagem: o PC que desliga não gera evento (online sai do lastSeen).
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    );

Future<void> iniciarServicoAula() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'servidor_aula',
      channelName: 'Servidor da aula',
      channelDescription: 'Mantém o servidor da aula ativo com a tela apagada.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: _opcoes(),
  );
  // Android 13+: sem esta permissão a notificação some, mas o serviço roda.
  final perm = await FlutterForegroundTask.checkNotificationPermission();
  if (perm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (await FlutterForegroundTask.isRunningService) {
    // Já rodava (boot, atualização, Android ou abertura anterior): grava as
    // opções desta versão e recria a tarefa, que relê conta, escola e aula
    // e renova a reserva na hora.
    await FlutterForegroundTask.updateService(
      foregroundTaskOptions: _opcoes(),
      callback: startCallback,
    );
    await FlutterForegroundTask.restartService();
    return;
  }
  await FlutterForegroundTask.startService(
    notificationTitle: 'Servidor da aula ativo',
    notificationText: textoDaBarra(0),
    callback: startCallback,
  );
}

Future<void> pararServicoAula() async {
  if (!await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.stopService();
}

/// Com o serviço de pé, só ele renova a reserva ([telaRenovaReservas]).
Future<bool> servicoAulaRodando() => FlutterForegroundTask.isRunningService;

// O handle fica gravado para o boot: não mover nem renomear.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AulaTaskHandler());
}

Future<String?> _abrirConta() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  return FirebaseAuth.instance.currentUser?.uid;
}

/// Tarefa do serviço. [contaAtual] (uid salvo, null = sem conta) e [push]
/// são injetáveis para testes.
class AulaTaskHandler extends TaskHandler {
  AulaTaskHandler({Future<String?> Function()? contaAtual, PushService Function()? push})
      : _contaAtual = contaAtual ?? _abrirConta,
        _novoPush = push ?? PushService.new;

  final Future<String?> Function() _contaAtual;
  final PushService Function() _novoPush;
  final TextoDaBarra _barra = TextoDaBarra();
  PresencaDosPcs? _presenca;
  StreamSubscription<DatabaseEvent>? _aulas;
  PushService? _push;
  String? _uid;
  bool _reservasNoCache = false;
  final Stopwatch _desdeRenovacao = Stopwatch();
  Future<void>? _renovando;
  bool _parado = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final zerado = _barra.aoSubir(peloSistema: starter == TaskStarter.system);
    if (zerado != null) unawaited(FlutterForegroundTask.updateService(notificationText: zerado));
    try {
      final uid = await _contaAtual();
      if (uid == null || _parado) return; // sem conta: só a notificação
      // Toda subida, também a de cada abertura do app (que recria a tarefa):
      // o onTokenRefresh tem de viver no motor que fica com o app fechado.
      _push = _novoPush();
      unawaited(_push!.registrar(uid));
      final escola = (await PrefsStore.load()).schoolUid;
      if (_parado) return;
      _uid = uid;
      _presenca = PresencaDosPcs(
        rosterPath: escola != null ? 'school/devices' : 'teachers/$uid/devices',
      )
        ..onChange = _atualizarBarra
        ..iniciar();
      if (escola != null) {
        // Com o nó no cache, a transação da renovação acerta de primeira.
        _aulas = FirebaseDatabase.instance.ref('school/aulas').onValue.listen(
          (_) {
            _reservasNoCache = true;
            _talvezRenovar();
          },
          onError: (Object e) => debugPrint('[CdA] serviço: reservas: $e'),
        );
      }
    } catch (e) {
      debugPrint('[CdA] serviço não começou: $e');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _atualizarBarra();
    _talvezRenovar();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _parado = true;
    await _aulas?.cancel();
    await _presenca?.parar();
    await _push?.parar();
    // O plugin do banco espera, sem prazo, a resposta do motor que começou a
    // transação: o motor só morre depois dela, por mais que ela demore.
    await _renovando;
  }

  void _atualizarBarra() {
    final texto = _barra.aoContar(_presenca?.online());
    if (texto == null || _parado) return;
    unawaited(FlutterForegroundTask.updateService(notificationText: texto));
  }

  void _talvezRenovar() {
    final uid = _uid, presenca = _presenca;
    if (_parado || uid == null || presenca == null || !_reservasNoCache) return;
    if (!presenca.conectado || _renovando != null) return;
    if (_desdeRenovacao.isRunning && _desdeRenovacao.elapsed < kRenovacao) return;
    _desdeRenovacao
      ..reset()
      ..start();
    _renovando = _renovar(uid, presenca)
        .catchError((Object e) => debugPrint('[CdA] serviço: renovar: $e'))
        .whenComplete(() => _renovando = null);
  }

  Future<void> _renovar(String uid, PresencaDosPcs presenca) async {
    final aula = await ClassSessionStore.load();
    final renovar = deveRenovar(
      aulaAtiva: aula.ativa,
      inicioMs: aula.inicio.millisecondsSinceEpoch,
      agoraMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!renovar || _parado) return;
    await renovarReservas(
      uid: uid,
      pcs: aula.vinculos.keys,
      agoraMs: presenca.relogio.agora().millisecondsSinceEpoch,
    );
  }
}
