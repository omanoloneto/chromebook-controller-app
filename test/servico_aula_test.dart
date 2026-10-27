// Tarefa do serviço em primeiro plano ao subir: o token do push e o texto da
// notificação fixa, pelo canal do plugin (presença e reserva dependem do
// Firebase e ficam de fora).

import 'package:controle_de_aula/src/service/foreground_service.dart';
import 'package:controle_de_aula/src/service/push_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

class _PushFalso extends PushService {
  final List<String> registrados = [];
  bool parado = false;

  @override
  Future<void> registrar(String uid) async => registrados.add(uid);

  @override
  Future<void> parar() async => parado = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('flutter_foreground_task/methods');
  late List<Object?> textos;

  setUp(() {
    textos = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (call) async {
      if (call.method == 'isRunningService') return true;
      if (call.method == 'updateService') textos.add((call.arguments as Map)['notificationContentText']);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null);
  });

  Future<_PushFalso> subirEDescer(TaskStarter quem, {String? uid = 'uid-prof'}) async {
    final push = _PushFalso();
    final tarefa = AulaTaskHandler(contaAtual: () async => uid, push: () => push);
    await tarefa.onStart(DateTime.now(), quem);
    await tarefa.onDestroy(DateTime.now(), false);
    return push;
  }

  test('toda subida regrava o token e ouve a renovação, também a de cada abertura do app', () async {
    for (final quem in TaskStarter.values) {
      final push = await subirEDescer(quem);
      expect(push.registrados, ['uid-prof'], reason: '$quem');
      expect(push.parado, isTrue, reason: 'a tarefa que sai para de ouvir; a nova ouve');
    }
  });

  test('sem conta salva, nada a registrar', () async {
    final push = await subirEDescer(TaskStarter.system, uid: null);
    expect(push.registrados, isEmpty);
  });

  test('subindo pelo sistema, a barra volta a 0; pelo app, fica a contagem de agora', () async {
    await subirEDescer(TaskStarter.developer);
    expect(textos, isEmpty);
    await subirEDescer(TaskStarter.system, uid: null);
    expect(textos, ['0 PC(s) conectados'], reason: 'boot sem internet: nada de número de ontem');
  });
}
