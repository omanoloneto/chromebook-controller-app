// Testes do cadastro de turmas/alunos e da sessão de aula (persistência
// local — nada disso vai ao Firebase).

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/pairing/class_session_store.dart';
import 'package:controle_de_aula/src/pairing/students_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cda_test_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('StudentsStore', () {
    test('CRUD de turmas e alunos persiste entre loads', () async {
      var store = await StudentsStore.load(dir: tmp);
      await store.adicionarTurma('2º ano A');
      await store.adicionarAluno(0, 'William');
      await store.adicionarAluno(0, 'Maria');

      store = await StudentsStore.load(dir: tmp);
      expect(store.turmas, hasLength(1));
      expect(store.turmas[0].nome, '2º ano A');
      expect(store.turmas[0].alunos, ['William', 'Maria']);

      await store.renomearAluno(0, 0, 'William S.');
      await store.removerAluno(0, 1);
      await store.renomearTurma(0, '2º ano B');

      store = await StudentsStore.load(dir: tmp);
      expect(store.turmas[0].nome, '2º ano B');
      expect(store.turmas[0].alunos, ['William S.']);

      await store.removerTurma(0);
      store = await StudentsStore.load(dir: tmp);
      expect(store.turmas, isEmpty);
    });

    test('rejeita duplicatas e entradas vazias', () async {
      final store = await StudentsStore.load(dir: tmp);
      await store.adicionarTurma('A');
      await store.adicionarTurma('A'); // duplicada
      await store.adicionarTurma('  '); // vazia
      expect(store.turmas, hasLength(1));

      await store.adicionarAluno(0, 'Zé');
      await store.adicionarAluno(0, 'Zé'); // duplicado
      await store.adicionarAluno(0, ''); // vazio
      await store.adicionarAluno(9, 'fora'); // índice inválido
      expect(store.turmas[0].alunos, ['Zé']);
    });

    test('arquivo corrompido/malformado recomeça vazio', () async {
      await File('${tmp.path}/turmas.json').writeAsString('{não é json');
      var store = await StudentsStore.load(dir: tmp);
      expect(store.turmas, isEmpty);

      // Entradas malformadas são puladas, válidas sobrevivem.
      await File('${tmp.path}/turmas.json').writeAsString(
        jsonEncode([
          {'nome': 'ok', 'alunos': ['a', 42, '', 'b']},
          {'semNome': true},
          'string solta',
        ]),
      );
      store = await StudentsStore.load(dir: tmp);
      expect(store.turmas, hasLength(1));
      expect(store.turmas[0].alunos, ['a', 'b']);
    });
  });

  group('ClassSessionStore', () {
    test('iniciar/vincular/encerrar persiste entre loads', () async {
      var s = await ClassSessionStore.load(dir: tmp);
      expect(s.ativa, false);

      await s.iniciar('2º ano A');
      await s.vincular('pc1', 'William');
      await s.vincular('pc2', 'Maria');

      s = await ClassSessionStore.load(dir: tmp);
      expect(s.ativa, true);
      expect(s.turma, '2º ano A');
      expect(s.alunoDe('pc1'), 'William');
      expect(s.vinculos, hasLength(2));

      await s.encerrar();
      s = await ClassSessionStore.load(dir: tmp);
      expect(s.ativa, false);
      expect(s.vinculos, isEmpty);
    });

    test('aluno só pode estar em um PC por vez', () async {
      final s = await ClassSessionStore.load(dir: tmp);
      await s.iniciar('A');
      await s.vincular('pc1', 'William');
      await s.vincular('pc2', 'William'); // mudou de PC
      expect(s.alunoDe('pc1'), isNull);
      expect(s.alunoDe('pc2'), 'William');
    });

    test('não vincula sem aula ativa; iniciar limpa vínculos antigos', () async {
      final s = await ClassSessionStore.load(dir: tmp);
      await s.vincular('pc1', 'X'); // sem aula
      expect(s.vinculos, isEmpty);

      await s.iniciar('A');
      await s.vincular('pc1', 'X');
      await s.iniciar('B'); // aula nova zera
      expect(s.vinculos, isEmpty);
      expect(s.turma, 'B');
    });
  });

  group('buildCloseAllTabs', () {
    test('shape do payload (paridade com o protocolo v4)', () {
      final padrao = buildCloseAllTabs();
      expect(padrao['type'], 'close_all_tabs');
      expect(padrao['v'], 1);
      expect(padrao['payload'], {'closeWindows': false});

      final encerrar = buildCloseAllTabs(closeWindows: true);
      expect(encerrar['payload'], {'closeWindows': true});
      expect(encerrar['id'], isNot(padrao['id'])); // ids monotônicos
    });
  });
}
