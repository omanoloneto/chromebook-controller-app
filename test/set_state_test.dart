// setStateOne: cada comando de estado vai para o seu nó; tipo desconhecido
// LANÇA (antes caía em 'rules' e sobrescreveria as regras do PC).

import 'package:controle_de_aula/src/cloud/firebase_transport.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nós de estado conhecidos', () {
    expect(noDeEstado(MessageType.setRules), 'rules');
    expect(noDeEstado(MessageType.setWallpaper), 'wallpaper');
    expect(noDeEstado(MessageType.setClassView), 'classview');
    expect(noDeEstado(MessageType.setUnit), 'unit');
    expect(noDeEstado(MessageType.setLock), 'lock');
    expect(noDeEstado(MessageType.setExam), 'exam');
    expect(noDeEstado(MessageType.setMonitor), 'monitor');
  });

  test('os builders novos caem nos nós novos', () {
    expect(noDeEstado(buildSetLock(rev: 1, on: true, texto: 'x', mute: true, ate: 2)['type']), 'lock');
    expect(noDeEstado(buildSetExam(rev: 1, on: true, allow: const [], ate: 2)['type']), 'exam');
    expect(noDeEstado(buildSetMonitor(rev: 1, ate: 2)['type']), 'monitor');
  });

  test('tipo desconhecido ou de fila lança', () {
    expect(() => noDeEstado('set_qualquer'), throwsArgumentError);
    expect(() => noDeEstado(null), throwsArgumentError);
    expect(() => noDeEstado(MessageType.openUrl), throwsArgumentError);
    expect(() => noDeEstado(MessageType.chatMessage), throwsArgumentError);
  });
}
