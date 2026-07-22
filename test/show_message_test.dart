// show_message: payload com/sem popup (mensagem individual, ext >= 0.4.8).

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sem popup: payload clássico (avisos do telão intocados)', () {
    final cmd = buildShowMessage('⚠ William', 'youtube.com');
    expect(cmd['type'], MessageType.showMessage);
    expect(cmd['payload'], {'title': '⚠ William', 'body': 'youtube.com'});
  });

  test('com popup: inclui popup e de', () {
    final cmd = buildShowMessage(
      'Mensagem do professor',
      'Volte para a atividade.',
      popup: true,
      de: 'Prof. Manoel',
    );
    expect(cmd['payload'], {
      'title': 'Mensagem do professor',
      'body': 'Volte para a atividade.',
      'popup': true,
      'de': 'Prof. Manoel',
    });
  });

  test('de sem popup não vaza', () {
    final cmd = buildShowMessage('t', 'b', de: 'Prof');
    expect((cmd['payload'] as Map).containsKey('de'), false);
    expect((cmd['payload'] as Map).containsKey('popup'), false);
  });
}
