// Aba Aula sem aula: as ações gerais com "Começar aula" no lugar das fotos de
// entrada (que ficam no ⋮), e o atalho para cadastrar a primeira turma.

import 'package:controle_de_aula/src/pairing/students_store.dart';
import 'package:controle_de_aula/src/ui/aula_page.dart';
import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

Future<FakePairing> _abrir(
  WidgetTester tester, {
  List<Turma> turmas = const [],
  VoidCallback? onIrParaTurmas,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = FakePairing()
    ..iniciando = false
    ..aulaAtivaFake = false
    ..schoolUid = 'escola'
    ..turmasFake = turmas
    ..pc('a', nome: 'Unidade 1');
  addTearDown(p.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AulaPage(pairing: p, onIrParaSites: () {}, onIrParaTurmas: onIrParaTurmas),
    ),
  );
  await tester.pump();
  return p;
}

void main() {
  testWidgets('sem aula: Começar aula no lugar das fotos de entrada, que vão para o ⋮',
      (tester) async {
    await _abrir(tester, turmas: [Turma(nome: '7ºA', alunos: ['Ana'])]);
    final rotulos = [
      for (final b in tester.widgetList<BotaoDeAcao>(find.byType(BotaoDeAcao))) b.rotulo,
    ];
    expect(rotulos, ['Abrir site', 'Conectar', 'Começar aula', 'Desligar']);
    expect(find.text('Começar uma aula'), findsNothing, reason: 'o cartão saiu');

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    expect(find.text('Fotos de início de sessão'), findsOneWidget);
    expect(find.text('Conectar computador'), findsOneWidget);
  });

  testWidgets('Começar aula pergunta a turma', (tester) async {
    final p = await _abrir(tester, turmas: [Turma(nome: '7ºA', alunos: ['Ana'])]);
    await tester.tap(find.text('Começar aula'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar aula com qual turma?'), findsOneWidget);
    await tester.tap(find.text('7ºA'));
    await tester.pumpAndSettle();
    expect(p.aulasIniciadas, ['7ºA']);
  });

  testWidgets('sem turma, Começar aula leva à aba Turmas', (tester) async {
    var turmas = 0;
    await _abrir(tester, onIrParaTurmas: () => turmas++);
    await tester.tap(find.text('Começar aula'));
    await tester.pump();
    expect(turmas, 1);
    expect(find.text('Cadastre a primeira turma para começar uma aula.'), findsOneWidget);
  });
}
