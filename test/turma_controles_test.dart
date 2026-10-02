// Controles de turma do app (SPEC-turma §5.4, §7.4, §8.4): o sheet de
// "Olhos em mim", os chips de trava, a grade de telas (liga só quando está
// na frente) e o botão do modo prova.

import 'dart:typed_data';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/ui/grade_telas.dart';
import 'package:controle_de_aula/src/ui/prova_controles.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:controle_de_aula/src/ui/trava_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

void _telaGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Uma tela com um botão que chama [acao] (o contexto tem Scaffold).
Widget _comBotao(void Function(BuildContext) acao) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () => acao(ctx),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

FakePairing _turma() {
  final p = FakePairing()
    ..pc('a', nome: 'Ana')
    ..pc('b', nome: 'Bruno', online: false)
    ..pc('c', nome: 'Caio');
  return p;
}

void main() {
  group('Olhos em mim', () {
    testWidgets('texto pronto trava a turma em 2 toques, com som desligado',
        (tester) async {
      _telaGrande(tester);
      final p = _turma();
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => travarComSheet(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Travar as telas da turma'), findsOneWidget);
      expect(
        find.text(
          'Os 3 computadores com aluno nesta aula mostram a mensagem em tela '
          'cheia até você destravar.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Olhos no professor'));
      await tester.pumpAndSettle();
      expect(p.travas.single.texto, 'Olhos no professor');
      expect(p.travas.single.mute, isTrue);
      expect(p.travas.single.apenas, isNull);
    });

    testWidgets('som ligado e texto personalizado', (tester) async {
      _telaGrande(tester);
      final p = _turma();
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => travarComSheet(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Silenciar o som'));
      await tester.tap(find.text('Texto personalizado…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Guardem o celular');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Travar'));
      await tester.pumpAndSettle();
      expect(p.travas.single.texto, 'Guardem o celular');
      expect(p.travas.single.mute, isFalse);
    });

    testWidgets('Escolher computadores trava só os marcados', (tester) async {
      _telaGrande(tester);
      final p = _turma();
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => travarComSheet(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher computadores'));
      await tester.pumpAndSettle();
      expect(find.text('desligado — trava quando ligar'), findsOneWidget);
      final botao = find.widgetWithText(FilledButton, 'Travar 0 computadores');
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);
      await tester.tap(find.text('Caio'));
      await tester.pump();
      await tester.tap(find.text('Travar 1 computador'));
      await tester.pumpAndSettle();
      expect(p.travas.single.apenas, {'c'});
      expect(p.travas.single.texto, 'Olhos no professor');
    });

    testWidgets('sem aula: avisa e não abre o sheet', (tester) async {
      final p = _turma()..semTurma = 'Comece uma aula para usar com a turma.';
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => travarComSheet(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      expect(
        find.text('Comece uma aula para usar com a turma.'),
        findsOneWidget,
      );
      expect(find.text('Travar as telas da turma'), findsNothing);
    });

    testWidgets('chips: "Tela travada" e "Travada sem professor · Destravar"',
        (tester) async {
      final p = _turma()..travados.addAll(['a', 'c']);
      p.semProfessor.add('c');
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  Row(children: chipsDeTrava(ctx, p, 'a')),
                  Row(children: chipsDeTrava(ctx, p, 'b')),
                  Row(children: chipsDeTrava(ctx, p, 'c')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Tela travada'), findsOneWidget);
      expect(find.text('Travada sem professor'), findsOneWidget);
      await tester.tap(find.text('Destravar'));
      await tester.pump();
      expect(p.destravados, ['c']);
    });
  });

  group('grade de telas', () {
    Widget app(FakePairing p, {bool visivel = true}) => MaterialApp(
          theme: buildTheme(Brightness.light),
          navigatorObservers: [observadorDeRotas],
          home: Scaffold(body: GradeTelas(pairing: p, visivel: visivel)),
        );

    testWidgets('liga na frente; desliga com outra aba, outra tela e fundo',
        (tester) async {
      final p = _turma();
      addTearDown(p.dispose);
      await tester.pumpWidget(app(p));
      await tester.pump();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (1, 0));

      // Outra aba (IndexedStack mantém montada).
      await tester.pumpWidget(app(p, visivel: false));
      await tester.pump();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (1, 1));
      await tester.pumpWidget(app(p));
      await tester.pump();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (2, 1));

      // Outra tela por cima; diálogo não conta.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      showDialog<void>(
        context: nav.context,
        builder: (_) => const AlertDialog(content: Text('oi')),
      );
      await tester.pumpAndSettle();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (2, 1));
      nav.pop();
      await tester.pumpAndSettle();
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (2, 2));
      nav.pop();
      await tester.pumpAndSettle();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (3, 2));

      // App em segundo plano.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (3, 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (4, 3));

      // Sair da tela (aula encerrada, por exemplo).
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect((p.abrirGradeChamadas, p.fecharGradeChamadas), (4, 4));
    });

    testWidgets('um quadro por PC, em ordem de nome, com o estado de cada um',
        (tester) async {
      _telaGrande(tester);
      final p = _turma()..pc('d', nome: 'Duda', ext: '0.6.0');
      addTearDown(p.dispose);
      p.mapa['c']!.thumb =
          Miniatura(ts: kAgoraTeste - 1000, motivo: 'sem_sessao');
      await tester.pumpWidget(app(p));
      await tester.pump();
      expect(find.text('Carregando…'), findsOneWidget); // Ana
      expect(find.text('Desligado'), findsOneWidget); // Bruno
      expect(find.text('Ninguém logado'), findsOneWidget); // Caio
      expect(
        find.text('Versão antiga — atualize para ver a tela'),
        findsOneWidget,
      ); // Duda
      final ana = tester.getTopLeft(find.text('Ana'));
      final bruno = tester.getTopLeft(find.text('Bruno'));
      final caio = tester.getTopLeft(find.text('Caio'));
      expect(ana.dy, bruno.dy); // 2 colunas no celular
      expect(ana.dx, lessThan(bruno.dx));
      expect(caio.dy, greaterThan(ana.dy));
    });

    testWidgets('tocar na miniatura amplia; no Celita pede a tela inteira',
        (tester) async {
      _telaGrande(tester);
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('c', nome: 'Caio', ext: 'celita-0.14.0');
      addTearDown(p.dispose);
      p.mapa['a']!.thumb = Miniatura(ts: kAgoraTeste - 12000, jpeg: jpeg);
      p.mapa['c']!.thumb = Miniatura(ts: kAgoraTeste - 3000, jpeg: jpeg);
      await tester.pumpWidget(app(p));
      await tester.pump();

      // Chromebook: só amplia a miniatura.
      await tester.tap(find.text('Ana'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Miniatura da aba aberta neste computador.'),
        findsOneWidget,
      );
      expect(find.text('há 12 s'), findsNWidgets(2)); // quadro e ampliada
      expect(p.fotosDeTela, isEmpty);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pump(const Duration(milliseconds: 300));

      // Celita OS: pede capture_screen; sem resposta, fica a miniatura.
      await tester.tap(find.text('Caio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.fotosDeTela, ['c']);
      expect(
        find.text('A tela maior não veio agora — esta é a miniatura.'),
        findsOneWidget,
      );
    });

    testWidgets('abrir recusado (turma vazia) abre quando a turma aparece',
        (tester) async {
      final p = FakePairing()
        ..semTurma = 'Nenhum computador com aluno nesta aula ainda.';
      addTearDown(p.dispose);
      await tester.pumpWidget(app(p));
      await tester.pump();
      expect((p.abrirGradeChamadas, p.gradeAberta), (1, false));

      p
        ..semTurma = null
        ..pc('a', nome: 'Ana');
      p.avisar();
      await tester.pump();
      expect((p.abrirGradeChamadas, p.gradeAberta), (2, true));
      // Aberta: outras mudanças não pedem de novo.
      p.avisar();
      await tester.pump();
      expect(p.abrirGradeChamadas, 2);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(p.gradeAberta, isFalse);
    });

    testWidgets('sem aula: o motivo no lugar da grade', (tester) async {
      final p = FakePairing()
        ..semTurma = 'Comece uma aula para usar com a turma.';
      addTearDown(p.dispose);
      await tester.pumpWidget(app(p));
      expect(
        find.text('Comece uma aula para usar com a turma.'),
        findsOneWidget,
      );
    });
  });

  group('modo prova', () {
    testWidgets('lista vazia pergunta antes de ligar', (tester) async {
      final p = _turma();
      addTearDown(p.dispose);
      var editou = 0;
      await tester.pumpWidget(
        _comBotao(
          (c) => alternarProva(c, p, onEditarSites: () => editou++),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Lista de sites vazia'), findsOneWidget);
      await tester.tap(find.text('Editar lista'));
      await tester.pumpAndSettle();
      expect(editou, 1);
      expect(p.ligarProvaChamadas, 0);
    });

    testWidgets('versão antiga avisa; "Ligar mesmo assim" liga',
        (tester) async {
      final p = _turma()
        ..sites = ['wikipedia.org']
        ..pc('d', nome: 'Duda', ext: '0.6.0');
      addTearDown(p.dispose);
      await tester.pumpWidget(
        _comBotao((c) => alternarProva(c, p, onEditarSites: () {})),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Alguns computadores não vão entrar em modo prova'),
        findsOneWidget,
      );
      expect(find.textContaining('Duda'), findsOneWidget);
      expect(
        find.text('Os Chromebooks se atualizam sozinhos em algumas horas.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ligar mesmo assim'));
      await tester.pumpAndSettle();
      expect(p.ligarProvaChamadas, 1);
      expect(
        find.text('Modo prova ligado: só os sites permitidos abrem.'),
        findsOneWidget,
      );
    });

    testWidgets('desligar oferece Desfazer; o aviso sai sozinho',
        (tester) async {
      final p = _turma()
        ..sites = ['wikipedia.org']
        ..provaLigadaFake = true;
      addTearDown(p.dispose);
      await tester.pumpWidget(
        _comBotao((c) => alternarProva(c, p, onEditarSites: () {})),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(p.desligarProvaChamadas, 1);
      expect(find.text('Modo prova desligado.'), findsOneWidget);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(p.ligarProvaChamadas, 1);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
