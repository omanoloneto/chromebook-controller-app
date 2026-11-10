// Janela larga: barra lateral no lugar da de baixo, listas numa coluna central
// e ações numa linha só. A largura decide, não a plataforma.

import 'dart:io';

import 'package:controle_de_aula/src/pairing/prefs_store.dart';
import 'package:controle_de_aula/src/platform/host.dart';
import 'package:controle_de_aula/src/ui/app_shell.dart';
import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/layout.dart';
import 'package:controle_de_aula/src/ui/settings_controller.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:controle_de_aula/src/util/abrir_no_celular.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

const _wide = Size(1366, 768);
const _phone = Size(412, 915);

void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  _resize(tester, size);
  addTearDown(tester.view.reset);
  late final PrefsStore prefs;
  late final Directory dir;
  await tester.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('cda_wide_');
    prefs = await PrefsStore.load(dir: dir);
  });
  addTearDown(() => dir.delete(recursive: true));
  // Com a escola conectada as boas-vindas não abrem por cima das abas.
  final pairing = FakePairing()
    ..iniciando = false
    ..schoolUid = 'escola';
  addTearDown(pairing.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppShell(pairing: pairing, settings: SettingsController(prefs)),
    ),
  );
  await tester.pump();
}

Future<List<Offset>> _pumpActions(
  WidgetTester tester, {
  required double width,
  required int count,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: GradeDeAcoes(
              acoes: [
                for (var i = 0; i < count; i++)
                  BotaoDeAcao(icone: Icons.star, rotulo: 'A$i', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return [
    for (var i = 0; i < count; i++) tester.getTopLeft(find.text('A$i')),
  ];
}

int _firstRowCount(List<Offset> positions) =>
    positions.where((p) => p.dy == positions.first.dy).length;

void main() {
  group('shell', () {
    testWidgets('no celular a navegação fica embaixo', (tester) async {
      await _pumpShell(tester, _phone);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('na janela larga a navegação vai para a lateral', (tester) async {
      await _pumpShell(tester, _wide);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.text('Ajustes'));
      await tester.pump();
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 3);
    });

    testWidgets('as páginas medem a janela sem a barra lateral', (tester) async {
      await _pumpShell(tester, _wide);
      final pages = find.byType(IndexedStack);
      final rail = tester.getSize(find.byType(NavigationRail)).width;
      expect(rail, greaterThan(0));
      expect(MediaQuery.sizeOf(tester.element(pages)).width, tester.getSize(pages).width);
      expect(tester.getSize(pages).width, lessThanOrEqualTo(_wide.width - rail));
    });

    testWidgets('trocar de barra não zera as abas', (tester) async {
      await _pumpShell(tester, _wide);
      await tester.tap(find.text('Turmas'));
      await tester.pump();
      final before = tester.element(find.byType(IndexedStack));

      _resize(tester, _phone);
      await tester.pump();

      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
      expect(tester.element(find.byType(IndexedStack)), same(before));
    });
  });

  group('coluna central', () {
    Future<BuildContext> contextWith(WidgetTester tester, double width) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 700),
            padding: const EdgeInsets.only(bottom: 20),
          ),
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      return captured;
    }

    testWidgets('janela estreita não ganha margem', (tester) async {
      final context = await contextWith(tester, 412);
      expect(isWideLayout(context), isFalse);
      expect(contentSideMargin(context), 0);
      expect(recuoDaLista(context), const EdgeInsets.only(bottom: 44));
    });

    testWidgets('janela larga centraliza a lista', (tester) async {
      final context = await contextWith(tester, 1280);
      expect(isWideLayout(context), isTrue);
      expect(contentSideMargin(context), (1280 - kContentMaxWidth) / 2);
      expect(
        recuoDaLista(context, topo: 4, fundo: 88),
        const EdgeInsets.fromLTRB(200, 4, 200, 108),
      );
    });

    testWidgets('a largura de corte já é janela larga', (tester) async {
      final context = await contextWith(tester, kWideLayoutWidth);
      expect(isWideLayout(context), isTrue);
      expect(contentSideMargin(context), 0);
    });
  });

  group('grade de ações', () {
    testWidgets('no celular são 4 por linha', (tester) async {
      final positions = await _pumpActions(tester, width: 380, count: 8);
      expect(_firstRowCount(positions), 4);
    });

    testWidgets('com largura de sobra cabem todas numa linha', (tester) async {
      expect(_firstRowCount(await _pumpActions(tester, width: 846, count: 8)), 8);
      expect(_firstRowCount(await _pumpActions(tester, width: 846, count: 9)), 9);
    });

    testWidgets('poucas ações: 4 colunas no celular, a largura toda na janela', (tester) async {
      final phone = await _pumpActions(tester, width: 380, count: 3);
      expect(phone[1].dx - phone[0].dx, 95);
      final wide = await _pumpActions(tester, width: 780, count: 3);
      expect(wide[1].dx - wide[0].dx, 260);
    });

    testWidgets('quando não cabem, as linhas saem parecidas', (tester) async {
      final positions = await _pumpActions(tester, width: 720, count: 9);
      expect(_firstRowCount(positions), 5);
    });
  });

  group('abrir no aparelho do professor', () {
    test('só página da web passa', () {
      expect(webUriOf('https://exemplo.com/a?b=1'), isNotNull);
      expect(webUriOf('http://exemplo.com'), isNotNull);
      expect(webUriOf('HTTPS://exemplo.com'), isNotNull);
    });

    test('esquema que abre arquivo ou programa fica de fora', () {
      for (final url in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'smb://servidor/pasta',
        'intent://abrir#Intent;end',
        'data:text/html,oi',
        'exemplo.com',
        'https:///sem-host',
        '',
        'http://[',
      ]) {
        expect(webUriOf(url), isNull, reason: url);
      }
    });

    test('os textos seguem o aparelho', () {
      addTearDown(() => onComputerOverride = null);
      onComputerOverride = false;
      expect(ofThisDeviceText, 'do celular');
      expect(openHereText, 'Abrir no meu celular');
      expect(openHereIcon, Icons.smartphone);
      onComputerOverride = true;
      expect(ofThisDeviceText, 'deste computador');
      expect(openHereText, 'Abrir neste computador');
      expect(openHereIcon, Icons.computer_outlined);
    });
  });
}
