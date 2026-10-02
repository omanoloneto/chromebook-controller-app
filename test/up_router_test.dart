// Canal up/: destino pela reserva de aula, push id, teto de 20 por PC,
// silêncio por excesso, idade de 12 h e dedup por (deviceId, mid).

import 'package:controle_de_aula/src/cloud/up_router.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

const _alfabeto = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// Push id com o ms codificado (8 chars) + 12 chars de "aleatório".
String _push(int ms, [String sufixo = 'AAAAAAAAAAAA']) {
  final chars = List.filled(8, '-');
  var n = ms;
  for (var i = 7; i >= 0; i--) {
    chars[i] = _alfabeto[n % 64];
    n ~/= 64;
  }
  return chars.join() + sufixo;
}

UpMessage _msg(String mid, {String type = UpType.chat}) => UpMessage.fromMap({
      'sid': 1,
      'seq': 1,
      'ts': 1,
      'v': 1,
      'type': type,
      'mid': mid,
      'payload': type == UpType.chat ? {'texto': 'oi'} : const {},
    })!;

void main() {
  const agora = 1767369600000;

  test('destinoDoUp: os 4 casos', () {
    expect(
      destinoDoUp(modoEscola: false, reservadoPorOutro: true, reservadoPorMim: false),
      DestinoUp.mostrarENotificar,
      reason: 'sem escola: tudo é do professor vinculado',
    );
    expect(
      destinoDoUp(modoEscola: true, reservadoPorOutro: true, reservadoPorMim: false),
      DestinoUp.ignorar,
    );
    expect(
      destinoDoUp(modoEscola: true, reservadoPorOutro: false, reservadoPorMim: true),
      DestinoUp.mostrarENotificar,
    );
    expect(
      destinoDoUp(modoEscola: true, reservadoPorOutro: false, reservadoPorMim: false),
      DestinoUp.mostrar,
      reason: 'PC livre: todo MEMBRO vê, ninguém é notificado',
    );
  });

  test('pushIdMs decodifica os 8 primeiros caracteres', () {
    expect(pushIdMs(_push(agora)), agora);
    expect(pushIdMs(_push(0)), 0);
    // Push id real do Firebase (2026): começa com "-O".
    expect(pushIdMs('-OabcdefXYZ0123456789'), isNotNull);
    expect(pushIdMs('curto'), isNull);
    expect(pushIdMs('com espaco 123'), isNull);
  });

  test('item com mais de 12 h é apagado sem ler', () {
    final r = UpRouter();
    final velho = _push(agora - const Duration(hours: 12, minutes: 1).inMilliseconds);
    final c = r.aoChegar('pc1', velho, agora);
    expect(c.ler, isFalse);
    expect(c.apagar, [velho]);
    final quase = _push(agora - const Duration(hours: 11).inMilliseconds);
    expect(r.aoChegar('pc1', quase, agora).ler, isTrue);
  });

  test('teto de 20 pendentes por PC: os mais antigos são apagados sem ler', () {
    final r = UpRouter();
    final chaves = [
      for (var i = 0; i < 22; i++) _push(agora - const Duration(hours: 1).inMilliseconds + i * 1000),
    ];
    final apagadas = <String>[];
    for (final k in chaves) {
      final c = r.aoChegar('pc1', k, agora);
      expect(c.ler, isTrue);
      apagadas.addAll(c.apagar);
    }
    expect(apagadas, [chaves[0], chaves[1]]);
    // Outro PC tem a própria conta.
    expect(r.aoChegar('pc2', chaves[0], agora).apagar, isEmpty);
  });

  test('mais de 20 itens novos em 10 min silenciam o PC por 10 min', () {
    final r = UpRouter();
    var silenciou = 0;
    for (var i = 0; i < 21; i++) {
      final c = r.aoChegar('pc1', _push(agora - 60000 + i * 100), agora);
      if (c.silenciou) silenciou++;
      if (i < 20) expect(c.ler, isTrue, reason: 'item $i');
      if (i == 20) expect(c.ler, isFalse);
    }
    expect(silenciou, 1, reason: 'a linha em Recados aparece uma vez');
    expect(r.silenciadoAte('pc1', agora), agora + 600000);
    // Ainda silenciado: não lê.
    expect(r.aoChegar('pc1', _push(agora + 1000), agora + 1000).ler, isFalse);
    // Passou o silêncio: volta a ler.
    const depois = agora + 600001;
    expect(r.silenciadoAte('pc1', depois), isNull);
    expect(r.aoChegar('pc1', _push(depois), depois).ler, isTrue);
  });

  test('reidratação (itens antigos de até 2 h) não silencia', () {
    final r = UpRouter();
    for (var i = 0; i < 20; i++) {
      final c = r.aoChegar('pc1', _push(agora - 7200000 + i * 60000), agora);
      expect(c.silenciou, isFalse);
    }
  });

  test('dedup por (deviceId, mid); o item sai quando a última chave some', () {
    final r = UpRouter();
    final k1 = _push(agora - 2000), k2 = _push(agora - 1000);
    r.aoChegar('pc1', k1, agora);
    r.aoChegar('pc1', k2, agora);
    expect(r.aoLer('pc1', k1, _msg('m1')), isTrue);
    expect(r.aoLer('pc1', k2, _msg('m1')), isFalse, reason: 'reenvio com o mesmo mid');
    expect(r.aoLer('pc2', k1, _msg('m1')), isTrue, reason: 'outro PC');
    expect(r.chavesDe('pc1', 'm1'), unorderedEquals([k1, k2]));
    expect(r.aoRemover('pc1', k1), isNull, reason: 'ainda há uma chave');
    expect(r.aoRemover('pc1', k2), 'm1');
    expect(r.chavesDe('pc1', 'm1'), isEmpty);
  });

  test('limparPc esquece tudo do PC', () {
    final r = UpRouter();
    final k = _push(agora);
    r.aoChegar('pc1', k, agora);
    r.aoLer('pc1', k, _msg('m1'));
    r.limparPc('pc1');
    expect(r.chavesDe('pc1', 'm1'), isEmpty);
    expect(r.aoLer('pc1', k, _msg('m1')), isTrue);
  });
}
