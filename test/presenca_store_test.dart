// Presença da chamada na sessão de aula: vale sem PC, o vínculo também conta,
// a falta tira dos dois, e tudo sobrevive ao app fechar e reabrir.

import 'dart:io';

import 'package:controle_de_aula/src/pairing/class_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('presenca'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('presença sem PC, vínculo e falta', () async {
    final s = await ClassSessionStore.load(dir: dir);
    await s.marcarPresente('Ana');
    expect(s.presente('Ana'), isFalse, reason: 'sem aula não marca');

    await s.iniciar('7ºA');
    await s.marcarPresente('Ana');
    await s.vincular('pc-b', 'Bruno');
    expect(s.presente('Ana'), isTrue);
    expect(s.presente('Bruno'), isTrue, reason: 'quem está num PC está presente');
    expect(s.presente('Caio'), isFalse);

    await s.desvincular('pc-b');
    expect(s.presente('Bruno'), isTrue, reason: 'sair do PC não é falta');

    await s.marcarFalta('Ana');
    await s.vincular('pc-a', 'Caio');
    await s.marcarFalta('Caio');
    expect(s.presente('Ana'), isFalse);
    expect(s.presente('Caio'), isFalse);
    expect(s.alunoDe('pc-a'), isNull);
    expect(s.presentes, {'Bruno'});
  });

  test('sobrevive ao reabrir e some ao iniciar ou encerrar', () async {
    var s = await ClassSessionStore.load(dir: dir);
    await s.iniciar('7ºA');
    await s.marcarPresente('Ana');

    s = await ClassSessionStore.load(dir: dir);
    expect(s.presentes, {'Ana'});

    await s.iniciar('8ºB');
    expect(s.presentes, isEmpty);
    await s.marcarPresente('Eva');
    await s.encerrar();
    expect(s.presentes, isEmpty);
  });
}
