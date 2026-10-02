// Confirmação de entrega (SPEC-turma §6): acks, timeout de 25 s, offline,
// ack tardio, aplicado.acks, versão antiga, estado (trava/prova) e textos.

import 'package:controle_de_aula/src/cloud/entrega.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 2, 10, 42);

Entrega _comando(Map<String, ({bool online, bool novo})> pcs, {bool comandoNovo = false}) {
  final e = Entrega(tipo: TipoEntrega.comando, enviadoEm: _t0);
  pcs.forEach((id, p) {
    e.adicionar(
      id,
      cmdId: 'id-$id',
      online: p.online,
      suportaTurma: p.novo,
      comandoNovo: comandoNovo,
    );
  });
  return e;
}

void main() {
  group('comandos (ack)', () {
    test('no envio: offline = desligado; o resto = enviando', () {
      final e = _comando({
        'a': (online: true, novo: true),
        'b': (online: false, novo: true),
      });
      expect(e.pc('a')!.estado, EstadoEntregaPc.enviando);
      expect(e.pc('b')!.estado, EstadoEntregaPc.desligado);
      expect(e.resolvida, isFalse);
      expect(textoEntrega(e), 'Enviando… 0 de 2');
    });

    test('comando novo em PC antigo começa como versão antiga', () {
      final e = _comando({'a': (online: true, novo: false)}, comandoNovo: true);
      expect(e.pc('a')!.estado, EstadoEntregaPc.versaoAntiga);
      // Comando antigo (ex.: open_url) num PC antigo: normal.
      final f = _comando({'a': (online: true, novo: false)});
      expect(f.pc('a')!.estado, EstadoEntregaPc.enviando);
    });

    test('ack ok = recebeu; ack com erro guarda o código', () {
      final e = _comando({'a': (online: true, novo: true), 'b': (online: true, novo: true)});
      expect(e.aoAck('a', 'id-a', ok: true), isTrue);
      expect(e.aoAck('b', 'id-b', ok: false, error: 'aba_falhou'), isTrue);
      expect(e.pc('a')!.estado, EstadoEntregaPc.recebeu);
      expect(e.pc('b')!.estado, EstadoEntregaPc.erro);
      expect(e.pc('b')!.codigo, 'aba_falhou');
      expect(e.resolvida, isTrue);
      expect(textoEntrega(e), '✓ 1 de 2 receberam · 1 com erro');
    });

    test('ack de id alheio ou de outro PC não muda nada', () {
      final e = _comando({'a': (online: true, novo: true)});
      expect(e.aoAck('a', 'id-de-outro-professor', ok: true), isFalse);
      expect(e.aoAck('b', 'id-a', ok: true), isFalse, reason: 'ack decifrado de outro PC');
      expect(e.pc('a')!.estado, EstadoEntregaPc.enviando);
    });

    test('25 s sem ack com o PC ligado = sem resposta; antes disso não', () {
      final e = _comando({'a': (online: true, novo: true), 'b': (online: true, novo: true)});
      e.aoAck('a', 'id-a', ok: true);
      expect(e.aoTempo(_t0.add(const Duration(seconds: 24))), isFalse);
      expect(e.pc('b')!.estado, EstadoEntregaPc.enviando);
      expect(e.aoTempo(_t0.add(kEntregaTimeout)), isTrue);
      expect(e.pc('b')!.estado, EstadoEntregaPc.semResposta);
      expect(textoEntrega(e), '✓ 1 de 2 receberam · 1 sem resposta');
    });

    test('ack tardio corrige depois do timeout e do "desligado"', () {
      final e = _comando({'a': (online: true, novo: true), 'b': (online: false, novo: true)});
      e.aoTempo(_t0.add(const Duration(seconds: 30)));
      expect(e.pc('a')!.estado, EstadoEntregaPc.semResposta);
      expect(e.aoAck('a', 'id-a', ok: true), isTrue);
      expect(e.aoAck('b', 'id-b', ok: true), isTrue, reason: 'PC ligou depois');
      expect(textoEntrega(e), '✓ Todos receberam (2)');
    });

    test('aplicado.acks conta como ack (app antigo apagou o ack)', () {
      final e = _comando({'a': (online: true, novo: true), 'b': (online: true, novo: true)});
      final aplicado = Aplicado.fromMap({
        'acks': [
          {'id': 'id-a', 'ok': true},
          {'id': 'outro', 'ok': true},
        ],
      })!;
      expect(e.aoAplicado('a', aplicado), isTrue);
      expect(e.pc('a')!.estado, EstadoEntregaPc.recebeu);
      // O relatório de 'a' não confirma o comando de 'b'.
      expect(e.aoAplicado('b', aplicado), isFalse);
      final comErro = Aplicado.fromMap({
        'acks': [
          {'id': 'id-b', 'ok': false, 'error': 'sem_sessao'},
        ],
      })!;
      expect(e.aoAplicado('b', comErro), isTrue);
      expect(e.pc('b')!.codigo, 'sem_sessao');
    });

    test('textos: todos, parcial completo e plural', () {
      final e = _comando({
        for (var i = 0; i < 20; i++) 'p$i': (online: i >= 2, novo: i != 19),
      }, comandoNovo: true,);
      for (var i = 2; i < 18; i++) {
        e.aoAck('p$i', 'id-p$i', ok: true);
      }
      e.aoTempo(_t0.add(const Duration(minutes: 1))); // p18 sem resposta
      expect(
        textoEntrega(e),
        '✓ 16 de 20 receberam · 2 desligados (recebem quando ligarem) · '
        '1 sem resposta · 1 com versão antiga',
      );
      final um = _comando({'a': (online: false, novo: true), 'b': (online: true, novo: true)});
      um.aoAck('b', 'id-b', ok: true);
      expect(textoEntrega(um), '✓ 1 de 2 receberam · 1 desligado (recebem quando ligarem)');
    });

    test('um PC só', () {
      Entrega e1(bool online) => _comando({'a': (online: online, novo: true)});
      final enviando = e1(true);
      expect(textoEntregaUmPc(enviando, 'Ana'), 'Enviando para Ana…');
      enviando.aoAck('a', 'id-a', ok: true);
      expect(textoEntregaUmPc(enviando, 'Ana'), 'Ana recebeu ✓');
      expect(textoEntregaUmPc(e1(false), 'Ana'), 'Ana está desligado — recebe quando ligar');
      final erro = e1(true)..aoAck('a', 'id-a', ok: false, error: 'url_invalida');
      expect(textoEntregaUmPc(erro, 'Ana'), 'Ana: O endereço do site não é válido.');
      final tempo = e1(true)..aoTempo(_t0.add(const Duration(seconds: 26)));
      expect(textoEntregaUmPc(tempo, 'Ana'), 'Ana não respondeu a tempo');
    });
  });

  group('estado (trava e prova, pelo aplicado)', () {
    Entrega trava({bool on = true}) {
      final e = Entrega(tipo: TipoEntrega.trava, enviadoEm: _t0, alvoOn: on, revEnviado: 100);
      e.adicionar('a', online: true, suportaTurma: true, comandoNovo: true);
      e.adicionar('b', online: true, suportaTurma: true, comandoNovo: true);
      e.adicionar('c', online: false, suportaTurma: true, comandoNovo: true);
      e.adicionar('v', online: true, suportaTurma: false, comandoNovo: true);
      return e;
    }

    Aplicado apl(int rev, bool on, [String? erro]) => Aplicado.fromMap({
          'trava': {'rev': rev, 'on': on, if (erro != null) 'erro': erro},
          'prova': {'rev': rev, 'on': on, if (erro != null) 'erro': erro},
        })!;

    test('confirma só com on igual e rev >= o enviado', () {
      final e = trava();
      expect(e.aoAplicado('a', apl(99, true)), isFalse, reason: 'rev velho');
      expect(e.aoAplicado('a', apl(100, false)), isFalse, reason: 'on diferente');
      expect(e.aoAplicado('a', apl(101, true)), isTrue, reason: 'renovação conta');
      expect(e.pc('a')!.estado, EstadoEntregaPc.recebeu);
    });

    test('sem_sessao e versão antiga na faixa; sem aplicado em 25 s = não travou', () {
      final e = trava();
      e.aoAplicado('a', apl(100, true));
      expect(textoTrava(e), 'Travando… 1 de 4', reason: 'b ainda sem confirmação');
      e.aoAplicado('b', apl(100, true, 'sem_sessao'));
      expect(e.resolvida, isTrue, reason: 'c desligado e v antigo não esperam');
      final f = trava();
      f.aoAplicado('a', apl(100, true));
      expect(f.resolvida, isFalse);
      f.aoTempo(_t0.add(const Duration(seconds: 25)));
      expect(
        textoTrava(f, desde: _t0),
        'Telas travadas: 1 de 4 · 1 desligado · 1 com versão antiga · 1 não travou · desde 10:42',
      );
      expect(
        textoTrava(e),
        'Telas travadas: 1 de 4 · 1 desligado · 1 com versão antiga · 1 sem ninguém logado',
      );
    });

    test('prova: navegador desatualizado e "não entrou"', () {
      final e = Entrega(tipo: TipoEntrega.prova, enviadoEm: _t0, revEnviado: 5);
      for (final id in ['a', 'b', 'c', 'd']) {
        e.adicionar(id, online: id != 'd', suportaTurma: true, comandoNovo: true);
      }
      e.aoAplicado('a', apl(5, true));
      e.aoAplicado('b', apl(5, true, 'navegador_antigo'));
      expect(textoProva(e), 'Ligando o modo prova… 1 de 4');
      e.aoTempo(_t0.add(const Duration(seconds: 30)));
      expect(
        textoProva(e),
        'Modo prova: 1 de 4 · 1 desligado · 1 com o navegador desatualizado · 1 não entrou',
      );
      expect(textoDoPc(e, e.pc('b')!), 'Navegador desatualizado');
      expect(textoDoPc(e, e.pc('c')!), 'Não entrou no modo prova');
    });

    test('a trava não confirma pela prova (e vice-versa)', () {
      final e = trava();
      final soProva = Aplicado.fromMap({
        'prova': {'rev': 200, 'on': true},
      })!;
      expect(e.aoAplicado('a', soProva), isFalse);
    });

    test('PC desligado que liga confirma ao vivo', () {
      final e = trava();
      expect(e.aoAplicado('c', apl(100, true)), isTrue);
      expect(e.pc('c')!.estado, EstadoEntregaPc.recebeu);
    });

    test('destravar tem textos próprios', () {
      final e = trava(on: false);
      expect(textoTrava(e), startsWith('Destravando…'));
      e.aoAplicado('a', apl(100, false));
      expect(textoDoPc(e, e.pc('a')!), 'Tela destravada ✓');
    });
  });
}
