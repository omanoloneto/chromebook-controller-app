// Notificação fixa do serviço: quantos PCs estão ligados (janela de 60 s no
// relógio do servidor), o texto só muda quando o número muda e volta a 0
// quando o sistema sobe o serviço.

import 'package:controle_de_aula/src/cloud/server_clock.dart';
import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/service/presenca_dos_pcs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agora = 1767369600000;

  test('contarOnline: presença de menos de 60 s, como PcSession.online', () {
    expect(contarOnline(const [], agora), 0);
    expect(
      contarOnline([agora, agora - 25000, agora - 59999, agora - 60000, agora - 3600000, null], agora),
      3,
    );
    expect(contarOnline([agora + 5000], agora), 1, reason: 'relógio do PC um pouco à frente');
    expect(kJanelaOnline, const Duration(seconds: 60));
  });

  test('contarOnline com o offset do relógio do servidor', () {
    final relogio = RelogioDoServidor()..aoReceberOffset(-90000);
    final servidor = relogio.agora().millisecondsSinceEpoch;
    final celular = DateTime.now().millisecondsSinceEpoch;
    // PC que bateu há 20 s no servidor: o celular adiantado 90 s ainda o vê.
    final lastSeen = [servidor - 20000];
    expect(contarOnline(lastSeen, servidor), 1);
    expect(contarOnline(lastSeen, celular), 0, reason: 'sem o offset, o PC some da conta');
  });

  test('o texto só muda quando o número muda', () {
    final barra = TextoDaBarra();
    expect(barra.aoContar(null), isNull, reason: 'contagem ainda a caminho');
    expect(barra.aoContar(0), '0 PC(s) conectados', reason: 'a 1ª contagem sempre escreve');
    expect(barra.aoContar(0), isNull);
    expect(barra.aoContar(3), '3 PC(s) conectados');
    expect(barra.aoContar(3), isNull);
    expect(barra.aoContar(null), isNull);
    expect(barra.aoContar(2), '2 PC(s) conectados');
    expect(textoDaBarra(1), '1 PC(s) conectados');
  });

  test('o sistema sobe o serviço: a barra volta a 0 até a contagem chegar', () {
    final barra = TextoDaBarra();
    expect(barra.aoSubir(peloSistema: false), isNull, reason: 'o app subiu: o texto é da contagem de agora');
    expect(barra.aoSubir(peloSistema: true), '0 PC(s) conectados');
    expect(barra.aoContar(null), isNull, reason: 'sem internet, fica o 0');
    expect(barra.aoContar(0), isNull, reason: 'já mostra 0');
    expect(barra.aoContar(4), '4 PC(s) conectados');
  });
}
