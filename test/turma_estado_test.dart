// Estado de turma no celular: trava/prova/liberações da prova persistem na
// sessão de aula, a lista de sites da prova (sites_prova.json), o alvo dos
// recursos de turma e as legendas dos balões do chat (SPEC-turma §3.6).

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/cloud/broadcast_target.dart';
import 'package:controle_de_aula/src/cloud/conversa.dart';
import 'package:controle_de_aula/src/pairing/class_session_store.dart';
import 'package:controle_de_aula/src/pairing/prova_store.dart';
import 'package:controle_de_aula/src/ui/textos_erro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cda_turma_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('ClassSessionStore (trava e prova)', () {
    test('trava, prova e liberações da prova persistem; encerrar limpa', () async {
      var s = await ClassSessionStore.load(dir: tmp);
      await s.iniciar('A');
      await s.definirTrava(
        const TravaDaAula(on: true, rev: 7, texto: 'Olhos no professor', mute: false, desde: 99),
      );
      await s.definirProva(const ProvaDaAula(on: true, rev: 8));
      await s.liberarNaProva('pc1', 'wikipedia.org');
      await s.liberarNaProva('pc1', 'wikipedia.org'); // repetido não duplica

      s = await ClassSessionStore.load(dir: tmp);
      expect(s.trava.on, isTrue);
      expect(s.trava.rev, 7);
      expect(s.trava.texto, 'Olhos no professor');
      expect(s.trava.mute, isFalse);
      expect(s.trava.desde, 99);
      expect(s.prova.on, isTrue);
      expect(s.prova.rev, 8);
      expect(s.provaLiberacoesDe('pc1'), {'wikipedia.org'});
      expect(s.provaLiberacoesDe('pc2'), isEmpty);

      await s.encerrar();
      s = await ClassSessionStore.load(dir: tmp);
      expect(s.trava.on, isFalse);
      expect(s.prova.on, isFalse);
      expect(s.provaLiberacoesDe('pc1'), isEmpty);
    });

    test('aula.json antigo (sem trava/prova) carrega desligado', () async {
      await File('${tmp.path}/aula.json').writeAsString(
        jsonEncode({'ativa': true, 'turma': 'A', 'inicio': 1, 'vinculos': {}, 'excecoes': {}}),
      );
      final s = await ClassSessionStore.load(dir: tmp);
      expect(s.ativa, isTrue);
      expect(s.trava.on, isFalse);
      expect(s.prova.on, isFalse);
    });
  });

  group('ProvaStore', () {
    test('adiciona normalizado, sem repetir; persiste com rev', () async {
      var p = await ProvaStore.load(dir: tmp);
      expect(p.padroes, isEmpty);
      expect(await p.adicionar('https://Wikipedia.org/'), isTrue);
      expect(await p.adicionar('wikipedia.org'), isFalse);
      expect(await p.adicionar('   '), isFalse);
      expect(await p.adicionarEmLote('khanacademy.org, geogebra.org\nwikipedia.org'), 2);
      final rev = p.rev;
      expect(rev, greaterThan(0));

      p = await ProvaStore.load(dir: tmp);
      expect(p.padroes, ['wikipedia.org', 'khanacademy.org', 'geogebra.org']);
      expect(p.rev, rev);

      await p.removerEm(1);
      await p.removerEm(9); // fora da lista: nada
      p = await ProvaStore.load(dir: tmp);
      expect(p.padroes, ['wikipedia.org', 'geogebra.org']);
    });

    test('arquivo corrompido vira lista vazia', () async {
      await File('${tmp.path}/${ProvaStore.fileName}').writeAsString('{nao é json');
      final p = await ProvaStore.load(dir: tmp);
      expect(p.padroes, isEmpty);
      expect(p.rev, 0);
    });
  });

  group('alvoDeTurma', () {
    test('sem aula ativa: vazio', () {
      expect(alvoDeTurma(aulaAtiva: false, vinculados: ['pc1']), isEmpty);
    });

    test('fora da escola: vinculados menos o telão', () {
      expect(
        alvoDeTurma(aulaAtiva: true, vinculados: ['pc1', 'telao', 'pc2'], pcProfessorId: 'telao'),
        ['pc1', 'pc2'],
      );
    });

    test('na escola: só os reservados por mim; nunca os de outro professor', () {
      expect(
        alvoDeTurma(
          aulaAtiva: true,
          vinculados: ['pc1', 'pc2', 'pc3'],
          modoEscola: true,
          reservadosPorMim: {'pc1', 'pc2'},
          reservadosPorOutros: {'pc2', 'pc3'},
        ),
        ['pc1'],
      );
    });
  });

  group('Balões do chat (§3.6)', () {
    ChatItem balao(EstadoBalao? e, {String? codigo, bool turma = false, bool antiga = false}) =>
        ChatItem(
          id: 'm',
          autor: AutorChat.professor,
          texto: 'oi',
          ts: 0,
          estado: e,
          codigoErro: codigo,
          paraTurma: turma,
          versaoAntiga: antiga,
        );

    test('legendas por estado', () {
      expect(legendaDoBalao(balao(EstadoBalao.enviando)), 'Enviando…');
      expect(legendaDoBalao(balao(EstadoBalao.entregue)), '✓ Entregue');
      expect(legendaDoBalao(balao(EstadoBalao.aguardando)), 'Aguardando (PC desligado)');
      expect(
        legendaDoBalao(balao(EstadoBalao.ninguemLogado)),
        'Ninguém logado — não entregue',
      );
      expect(legendaDoBalao(balao(EstadoBalao.semResposta)), 'Não respondeu a tempo');
      expect(legendaDoBalao(balao(null)), '');
    });

    test('erro: texto da tabela, nunca o código cru', () {
      final l = legendaDoBalao(balao(EstadoBalao.erro, codigo: 'chat_janela'));
      expect(l, 'Não foi possível entregar a mensagem.');
      expect(l.contains('chat_janela'), isFalse);
      expect(
        legendaDoBalao(balao(EstadoBalao.erro, codigo: kErroEnvioLocal)),
        kTextoSemInternet,
      );
    });

    test('para a turma e versão antiga entram na legenda', () {
      expect(
        legendaDoBalao(balao(EstadoBalao.entregue, turma: true)),
        '✓ Entregue · para a turma',
      );
      expect(
        legendaDoBalao(balao(EstadoBalao.enviando, antiga: true)),
        'Enviando… · Versão antiga: o aluno não consegue responder',
      );
    });
  });

  test('pedido repetido junta os mids e fica com o mais novo', () {
    final p = PedidoLiberacao(
      deviceId: 'pc1',
      mid: 'a',
      site: 'youtube.com',
      url: 'https://youtube.com/1',
      motivo: 'aula',
      bloqueio: 'regra',
      ts: 100,
    );
    p.juntar(mid: 'b', url: 'https://youtube.com/2', motivo: 'vídeo', bloqueio: 'regra', ts: 200);
    p.juntar(mid: 'c', url: 'https://youtube.com/0', motivo: 'velho', bloqueio: 'regra', ts: 50);
    expect(p.mids, {'a', 'b', 'c'});
    expect(p.mid, 'b');
    expect(p.url, 'https://youtube.com/2');
    expect(p.motivo, 'vídeo');
    expect(p.ts, 200);
  });
}
