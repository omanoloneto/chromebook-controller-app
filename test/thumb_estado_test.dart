// Grade de telas (SPEC-turma §5.4): cada linha da tabela de idade e frescor
// e as colunas pela largura.

import 'dart:typed_data';

import 'package:controle_de_aula/src/cloud/thumb_estado.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

const int _agora = 1000000000;
const int _abertaEm = _agora - 120000; // grade aberta há 2 min

final Uint8List _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

EstadoQuadro _estado({
  bool online = true,
  bool suporta = true,
  Miniatura? thumb,
  int? abertaEm = _abertaEm,
}) =>
    estadoDoQuadro(
      online: online,
      suportaTurma: suporta,
      thumb: thumb,
      gradeAbertaEm: abertaEm,
      agoraMs: _agora,
    );

Miniatura _imagem(int idadeMs) => Miniatura(ts: _agora - idadeMs, jpeg: _jpeg);
Miniatura _marcador(String motivo) =>
    Miniatura(ts: _agora - 1000, motivo: motivo);

void main() {
  group('tabela de §5.4', () {
    test('ainda sem miniatura desde que a grade abriu: "Carregando…"', () {
      final e = _estado();
      expect(e.tipo, TipoQuadro.carregando);
      expect(e.texto, 'Carregando…');
      expect(e.temImagem, isFalse);
    });

    test('PC offline: "Desligado" (mesmo com miniatura velha guardada)', () {
      final e = _estado(online: false, thumb: _imagem(2000));
      expect(e.tipo, TipoQuadro.desligado);
      expect(e.texto, 'Desligado');
    });

    test('PC sem suporte a turma: "Versão antiga — atualize para ver a tela"',
        () {
      final e = _estado(suporta: false);
      expect(e.tipo, TipoQuadro.versaoAntiga);
      expect(e.texto, 'Versão antiga — atualize para ver a tela');
    });

    test('marcador sem_sessao: "Ninguém logado"', () {
      final e = _estado(thumb: _marcador('sem_sessao'));
      expect(e.tipo, TipoQuadro.ninguemLogado);
      expect(e.texto, 'Ninguém logado');
    });

    test('marcador sem_permissao: "Miniatura não permitida neste Chromebook"',
        () {
      final e = _estado(thumb: _marcador('sem_permissao'));
      expect(e.tipo, TipoQuadro.naoPermitida);
      expect(e.texto, 'Miniatura não permitida neste Chromebook');
    });

    test('marcador aba_protegida ou falhou: "Tela indisponível agora"', () {
      for (final m in ['aba_protegida', 'falhou', 'qualquer_outro']) {
        final e = _estado(thumb: _marcador(m));
        expect(e.tipo, TipoQuadro.indisponivel, reason: m);
        expect(e.texto, 'Tela indisponível agora', reason: m);
      }
    });

    test('imagem com ts ≤ 30 s: imagem + "agora" / "há {s} s"', () {
      expect(_estado(thumb: _imagem(0)).texto, 'agora');
      expect(_estado(thumb: _imagem(4999)).texto, 'agora');
      final e = _estado(thumb: _imagem(12000));
      expect(e.tipo, TipoQuadro.imagem);
      expect(e.texto, 'há 12 s');
      expect(e.esmaecida, isFalse);
      final limite = _estado(thumb: _imagem(30000));
      expect(limite.texto, 'há 30 s');
      expect(limite.esmaecida, isFalse);
    });

    test('imagem com ts > 30 s: esmaecida + "há {n} min"', () {
      final e = _estado(thumb: _imagem(31000));
      expect(e.tipo, TipoQuadro.imagem);
      expect(e.esmaecida, isTrue);
      expect(e.texto, 'há 1 min'); // nunca "há 0 min"
      expect(_estado(thumb: _imagem(119000)).texto, 'há 2 min');
      expect(
        _estado(thumb: _imagem(10 * 60000), abertaEm: null).texto,
        'há 10 min',
      );
    });

    test('ts anterior à abertura da grade: trata como "Carregando…"', () {
      final velha = Miniatura(ts: _abertaEm - 1, jpeg: _jpeg);
      expect(_estado(thumb: velha).tipo, TipoQuadro.carregando);
      const marcadorVelho = Miniatura(ts: _abertaEm - 1, motivo: 'sem_sessao');
      expect(_estado(thumb: marcadorVelho).tipo, TipoQuadro.carregando);
      // Sem hora de abertura conhecida, vale a miniatura.
      expect(
        _estado(thumb: velha, abertaEm: null).tipo,
        TipoQuadro.imagem,
      );
    });

    test('relógio do PC à frente do servidor: idade nunca negativa', () {
      final futura = Miniatura(ts: _agora + 5000, jpeg: _jpeg);
      expect(_estado(thumb: futura).texto, 'agora');
    });
  });

  test('colunas: < 600 dp → 2; < 900 → 3; senão 4', () {
    expect(colunasDaGrade(360), 2);
    expect(colunasDaGrade(599.9), 2);
    expect(colunasDaGrade(600), 3);
    expect(colunasDaGrade(899), 3);
    expect(colunasDaGrade(900), 4);
    expect(colunasDaGrade(1600), 4);
  });
}
