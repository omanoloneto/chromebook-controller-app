// Diagnóstico de Wi-Fi e da tampa: o comando que o "Gravar diagnóstico" manda
// ao agente do Celita OS (protocolo: `diagnostico`).

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/util/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leva as horas no payload e um id por comando', () {
    final cmd = buildDiagnostico(kHorasDiagnostico);
    expect(cmd['v'], kProtocolVersion);
    expect(cmd['type'], 'diagnostico');
    expect(cmd['payload'], {'horas': 6});
    expect(formatoDeId.hasMatch(cmd['id'] as String), isTrue);
    expect(buildDiagnostico(0)['payload'], {'horas': 0});
    expect(buildDiagnostico(6)['id'], isNot(buildDiagnostico(6)['id']));
  });

  test('só o agente do Celita OS atende', () {
    expect(kComandosSoCelita, contains(MessageType.diagnostico));
  });
}
