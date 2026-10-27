// Travas de aula: decisão pura de expiração, da renovação (o que a transação
// grava), do teto e de quem renova (o resto é Firebase, coberto pelas rules no
// emulador — tests/rules-school.test.mjs na extensão).

import 'package:controle_de_aula/src/cloud/aula_locks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t0 = 1767369600000;

  test('trava fresca não expira; >15min sem heartbeat expira', () {
    expect(travaExpirada(ts: t0, agoraMs: t0 + 1), false);
    expect(travaExpirada(ts: t0, agoraMs: t0 + 14 * 60000), false);
    expect(travaExpirada(ts: t0, agoraMs: t0 + 15 * 60000), false); // limite
    expect(travaExpirada(ts: t0, agoraMs: t0 + 15 * 60000 + 1), true);
  });

  test('janela espelha as rules (900000 ms)', () {
    expect(kTravaExpira.inMilliseconds, 900000);
  });

  group('reservaRenovada (o que a transação grava)', () {
    test('nó apagado (aula encerrada): não recria, mas deixa o servidor conferir', () {
      final r = reservaRenovada(null, 'prof', t0);
      expect(r.aborted, isFalse, reason: 'abortar com o cache vazio não perguntaria ao servidor');
      expect(r.value, isNull);
    });

    test('reserva de outra pessoa: aborta, viva ou vencida', () {
      expect(reservaRenovada({'uid': 'bia', 'ts': t0, 'env': 'x'}, 'prof', t0 + 1000).aborted, isTrue);
      expect(
        reservaRenovada({'uid': 'bia', 'ts': t0 - 16 * 60000, 'env': 'x'}, 'prof', t0).aborted,
        isTrue,
      );
      expect(reservaRenovada({'ts': t0}, 'prof', t0 + 1000).aborted, isTrue, reason: 'nó sem dono');
      expect(reservaRenovada('lixo', 'prof', t0).aborted, isTrue);
    });

    test('reserva minha: ts novo, mesmo uid e mesmo env (também vencida)', () {
      for (final ts in [t0 - 60000, t0 - 16 * 60000]) {
        final r = reservaRenovada(<Object?, Object?>{'uid': 'prof', 'ts': ts, 'env': 'cifrado'}, 'prof', t0);
        expect(r.aborted, isFalse);
        expect(r.value, {'uid': 'prof', 'ts': t0, 'env': 'cifrado'});
      }
    });
  });

  group('deveRenovar (teto de 6 h desde o início da aula)', () {
    const hora = 60 * 60000;

    test('sem aula aberta não renova', () {
      expect(deveRenovar(aulaAtiva: false, inicioMs: t0, agoraMs: t0 + 1), isFalse);
    });

    test('renova até o teto e para depois dele', () {
      expect(deveRenovar(aulaAtiva: true, inicioMs: t0, agoraMs: t0), isTrue);
      expect(deveRenovar(aulaAtiva: true, inicioMs: t0, agoraMs: t0 + 6 * hora - 1), isTrue);
      expect(deveRenovar(aulaAtiva: true, inicioMs: t0, agoraMs: t0 + 6 * hora), isFalse);
      expect(
        deveRenovar(aulaAtiva: true, inicioMs: t0, agoraMs: t0 + 30 * hora),
        isFalse,
        reason: 'aula esquecida aberta não prende os PCs no dia seguinte',
      );
    });

    test('o teto é de 6 h', () {
      expect(kReservaTeto, const Duration(hours: 6));
    });
  });

  group('telaRenovaReservas (um dono só para a transação)', () {
    test('com o serviço de pé, o app aberto não abre transação', () {
      expect(telaRenovaReservas(servicoRodando: true, conectado: true), isFalse);
      expect(telaRenovaReservas(servicoRodando: true, conectado: false), isFalse);
    });

    test('sem o serviço, o app aberto renova, só com conexão', () {
      expect(telaRenovaReservas(servicoRodando: false, conectado: true), isTrue);
      expect(
        telaRenovaReservas(servicoRodando: false, conectado: false),
        isFalse,
        reason: 'feita sem rede, a transação roda de novo na volta, talvez com a tela já fechada',
      );
    });
  });
}
