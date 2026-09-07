// Comandos de imagem avulsa: foto da câmera (extensão e agente) e captura da
// tela (só o agente do Celita OS) — ver docs/protocolo.md §3.

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture_camera tem payload vazio e id próprio', () {
    final a = buildCaptureCamera();
    final b = buildCaptureCamera();
    expect(a['type'], 'capture_camera');
    expect(a['v'], kProtocolVersion);
    expect(a['payload'], isEmpty);
    expect(a['id'], isNot(b['id']));
  });

  test('capture_screen é um tipo separado da câmera', () {
    final tela = buildCaptureScreen();
    expect(tela['type'], 'capture_screen');
    expect(tela['type'], isNot(buildCaptureCamera()['type']));
    expect(tela['payload'], isEmpty);
  });
}
