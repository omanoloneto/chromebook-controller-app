// Relógio do servidor: a poda do arquivo só roda depois do offset real.

import 'package:controle_de_aula/src/cloud/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool> concluiu(RelogioDoServidor r) async {
    var ok = false;
    r.pronto.then((_) => ok = true);
    await Future<void>.delayed(Duration.zero);
    return ok;
  }

  test('antes de conectar vale o relógio do celular e não fica pronto', () async {
    final r = RelogioDoServidor();
    expect(r.offsetMs, 0);
    r.aoReceberOffset(null); // nó vazio antes do handshake
    r.aoMudarConexao(false);
    expect(await concluiu(r), isFalse);
  });

  test('offset real sem conexão ainda não basta', () async {
    final r = RelogioDoServidor()..aoReceberOffset(-864000000);
    expect(r.offsetMs, -864000000);
    expect(await concluiu(r), isFalse);
  });

  test('conectado sem offset não basta; com os dois fica pronto', () async {
    final r = RelogioDoServidor()..aoMudarConexao(true);
    expect(await concluiu(r), isFalse);
    r.aoReceberOffset(-864000000);
    expect(await concluiu(r), isTrue);
  });

  test('a ordem não importa: offset do handshake e depois connected', () async {
    final r = RelogioDoServidor()
      ..aoReceberOffset(1234)
      ..aoMudarConexao(true);
    expect(await concluiu(r), isTrue);
    final agora = DateTime.now().millisecondsSinceEpoch;
    expect(r.agora().millisecondsSinceEpoch - agora, closeTo(1234, 200));
  });
}
