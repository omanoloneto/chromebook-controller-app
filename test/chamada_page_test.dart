// Chamada da aula: tocar no aluno pergunta a unidade; atalhos das ligadas e
// livres; erro no próprio diálogo; troca com confirmação; falta; aluno novo;
// e a aula que começa pela chamada.

import 'package:controle_de_aula/src/pairing/chamada.dart';
import 'package:controle_de_aula/src/pairing/students_store.dart';
import 'package:controle_de_aula/src/ui/aula_page.dart';
import 'package:controle_de_aula/src/ui/chamada_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

FakePairing _sala() {
  final p = FakePairing()
    ..pc('a')
    ..pc('b')
    ..pc('c', online: false)
    ..turmaFake = '7ºA'
    ..alunosFake = ['Ana', 'Bruno', 'Caio'];
  p.numeros.addAll({'a': 1, 'b': 2, 'c': 3});
  return p;
}

Future<FakePairing> _abrir(
  WidgetTester tester, [
  void Function(FakePairing p)? preparar,
]) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = _sala();
  addTearDown(p.dispose);
  preparar?.call(p);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChamadaPage(pairing: p),
    ),
  );
  await tester.pump();
  return p;
}

Finder _atalho(String numero) => find.widgetWithText(ActionChip, numero);

Future<void> _digitar(WidgetTester tester, String numero) async {
  await tester.enterText(find.byType(TextField), numero);
  await tester.tap(find.widgetWithText(FilledButton, 'Presente'));
  await tester.pumpAndSettle();
}

void main() {
  test('regra da unidade: faixa, PC inexistente e telão', () {
    const faixa = 'Digite um número de 1 a 9999.';
    expect(motivoContraUnidade(null, deviceId: null, ehTelao: false), faixa);
    expect(motivoContraUnidade(0, deviceId: 'a', ehTelao: false), faixa);
    expect(motivoContraUnidade(10000, deviceId: 'a', ehTelao: false), faixa);
    expect(
      motivoContraUnidade(13, deviceId: null, ehTelao: false),
      'Nenhum PC é a unidade 13.',
    );
    expect(
      motivoContraUnidade(2, deviceId: 'b', ehTelao: true),
      'A unidade 2 é o telão.',
    );
    expect(motivoContraUnidade(2, deviceId: 'b', ehTelao: false), isNull);
  });

  testWidgets('lista a turma e conta os presentes', (tester) async {
    await _abrir(tester, (p) => p.vinculos['b'] = 'Bruno');
    expect(find.text('Chamada · 7ºA'), findsOneWidget);
    expect(find.text('1 de 3 presentes'), findsOneWidget);
    expect(find.text('Unidade 2'), findsOneWidget);
    expect(find.text('Marcar'), findsNWidgets(2));
  });

  testWidgets('tocar no aluno pergunta a unidade; o atalho de uma livre marca',
      (tester) async {
    final p = await _abrir(tester);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Unidade de Ana'), findsOneWidget);
    // Ligadas e livres: a 3 está desligada.
    expect(_atalho('1'), findsOneWidget);
    expect(_atalho('2'), findsOneWidget);
    expect(_atalho('3'), findsNothing);

    await tester.tap(_atalho('2'));
    await tester.pumpAndSettle();
    expect(p.presencas, [('Ana', 2)]);
    expect(find.text('Unidade 2'), findsOneWidget);
    expect(find.text('1 de 3 presentes'), findsOneWidget);
  });

  testWidgets('número digitado: inexistente erra no diálogo, o da desligada vale',
      (tester) async {
    final p = await _abrir(tester);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await _digitar(tester, '9');
    expect(find.text('Nenhum PC é a unidade 9.'), findsOneWidget);
    expect(p.presencas, isEmpty);

    await _digitar(tester, '3');
    expect(find.text('Unidade de Ana'), findsNothing);
    expect(p.presencas, [('Ana', 3)]);
    expect(find.text('Unidade 3'), findsOneWidget);
  });

  testWidgets('telão não recebe aluno nem aparece nos atalhos', (tester) async {
    final p = await _abrir(tester, (p) => p.telaoFake = 'b');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(_atalho('2'), findsNothing);
    await _digitar(tester, '2');
    expect(find.text('A unidade 2 é o telão.'), findsOneWidget);
    expect(p.presencas, isEmpty);
  });

  testWidgets('unidade com outro aluno pede para trocar', (tester) async {
    final p = await _abrir(tester, (p) => p.vinculos['a'] = 'Bruno');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(_atalho('1'), findsNothing, reason: 'a 1 não está livre');
    await _digitar(tester, '1');
    expect(find.text('Unidade 1 ocupada'), findsOneWidget);
    expect(find.textContaining('A unidade 1 está com Bruno'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Trocar'));
    await tester.pumpAndSettle();
    expect(p.presencas, [('Ana', 1)]);
    expect(p.pcDoAluno('Bruno'), isNull);
    expect(find.text('1 de 3 presentes'), findsOneWidget);
  });

  testWidgets('cancelar a troca não mexe em ninguém', (tester) async {
    final p = await _abrir(tester, (p) => p.vinculos['a'] = 'Bruno');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await _digitar(tester, '1');
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(p.presencas, isEmpty);
    expect(p.pcDoAluno('Bruno'), 'a');
  });

  testWidgets('aluno presente: trocar de unidade ou marcar falta', (tester) async {
    final p = await _abrir(tester, (p) => p.vinculos['a'] = 'Ana');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Presente na unidade 1'), findsOneWidget);
    await tester.tap(find.text('Trocar de unidade'));
    await tester.pumpAndSettle();
    expect(find.text('Unidade de Ana'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
      reason: 'o número atual já vem escrito',
    );
    await tester.tap(_atalho('2'));
    await tester.pumpAndSettle();
    expect(p.presencas, [('Ana', 2)]);

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar falta'));
    await tester.pumpAndSettle();
    expect(p.faltas, ['Ana']);
    expect(find.text('0 de 3 presentes'), findsOneWidget);
  });

  testWidgets('aluno novo é cadastrado e já pergunta a unidade', (tester) async {
    final p = await _abrir(tester);
    await tester.tap(find.byTooltip('Aluno novo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Dani ');
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
    await tester.pumpAndSettle();
    expect(p.cadastrados, ['Dani']);
    expect(find.text('Unidade de Dani'), findsOneWidget);
    await tester.tap(_atalho('1'));
    await tester.pumpAndSettle();
    expect(p.presencas, [('Dani', 1)]);
  });

  testWidgets('turma vazia leva ao cadastro', (tester) async {
    await _abrir(tester, (p) => p.alunosFake = []);
    expect(find.text('Nenhum aluno nesta turma ainda.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cadastrar aluno'), findsOneWidget);
  });

  testWidgets('a aula começa pela chamada, e a faixa da aula a reabre',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final p = _sala()
      ..iniciando = false
      ..aulaAtivaFake = false
      ..turmasFake = [
        Turma(nome: '8ºB', alunos: ['Eva', 'Gil']),
      ];
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: AulaPage(pairing: p, onIrParaSites: () {}),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Iniciar aula'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8ºB'));
    await tester.pumpAndSettle();
    expect(p.aulasIniciadas, ['8ºB']);
    expect(find.text('Chamada · 8ºB'), findsOneWidget);
    expect(find.text('0 de 2 presentes'), findsOneWidget);

    await tester.tap(find.text('Eva'));
    await tester.pumpAndSettle();
    await tester.tap(_atalho('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Concluir chamada'));
    await tester.pumpAndSettle();
    expect(find.text('Aula: 8ºB · 1/2 presentes'), findsOneWidget);

    await tester.tap(find.byTooltip('Fazer chamada'));
    await tester.pumpAndSettle();
    expect(find.text('Chamada · 8ºB'), findsOneWidget);
    expect(find.text('1 de 2 presentes'), findsOneWidget);
  });
}
