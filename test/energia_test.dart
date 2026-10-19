// Energia dos PCs com Celita OS (sair da conta, reiniciar, desligar): o
// comando, os bloqueios e a contagem do controller, a ação Desligar da tela do
// computador, o sheet da turma e o botão nas ações da aula (em 320 e 360 dp).

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/pairing/pairing_controller.dart';
import 'package:controle_de_aula/src/ui/aula_page.dart';
import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/device_page.dart';
import 'package:controle_de_aula/src/ui/energia_controles.dart';
import 'package:controle_de_aula/src/ui/textos_erro.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:controle_de_aula/src/util/ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

const _celita = 'celita-0.20.0';

/// Ana e Caio: ligados, com Celita OS, na aula. Bruno desligado, Duda num
/// Chromebook, Edu fora da aula.
FakePairing _sala() => FakePairing()
  ..pc('a', nome: 'Ana', ext: _celita)
  ..pc('b', nome: 'Bruno', ext: _celita, online: false)
  ..pc('c', nome: 'Caio', ext: _celita)
  ..pc('d', nome: 'Duda')
  ..pc('e', nome: 'Edu', ext: _celita, naTurma: false);

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

const _acoes = ['Sair da conta', 'Reiniciar', 'Desligar'];

void main() {
  group('comando', () {
    test('energia leva a ação no payload e um id por comando', () {
      const valores = {
        AcaoEnergia.encerrar: 'encerrar',
        AcaoEnergia.reiniciar: 'reiniciar',
        AcaoEnergia.desligar: 'desligar',
      };
      expect(AcaoEnergia.values, valores.keys.toList());
      valores.forEach((acao, valor) {
        final cmd = buildEnergia(acao);
        expect(cmd['v'], kProtocolVersion);
        expect(cmd['type'], 'energia');
        expect(cmd['payload'], {'acao': valor});
        expect(formatoDeId.hasMatch(cmd['id'] as String), isTrue);
      });
      expect(
        buildEnergia(AcaoEnergia.desligar)['id'],
        isNot(buildEnergia(AcaoEnergia.desligar)['id']),
      );
    });

    test('só o agente do Celita OS atende', () {
      expect(MessageType.energia, 'energia');
      expect(kComandosSoCelita, contains(MessageType.energia));
    });
  });

  group('controller', () {
    test('um PC: conectando, aula de outro, desligado e sem Celita barram',
        () async {
      final p = _sala()..outrosProfessores['c'] = 'Prof. Carlos';
      addTearDown(p.dispose);
      expect(
        await p.energiaNoPc('x', AcaoEnergia.desligar),
        'Ainda conectando — tente de novo.',
      );
      expect(
        await p.energiaNoPc('c', AcaoEnergia.desligar),
        'Está na aula de Prof. Carlos.',
      );
      expect(
        await p.energiaNoPc('b', AcaoEnergia.desligar),
        'O PC está desligado.',
      );
      expect(
        await p.energiaNoPc('d', AcaoEnergia.desligar),
        'Só os PCs com Celita OS desligam, reiniciam ou encerram a sessão pelo app.',
      );
      expect(p.energias, isEmpty);

      expect(await p.energiaNoPc('a', AcaoEnergia.encerrar), isNull);
      final e = p.energias.single;
      expect(e.alvos, ['a']);
      expect(e.acao, AcaoEnergia.encerrar);
      expect(e.umPc, isTrue, reason: 'a faixa fica na tela do PC');
    });

    test('turma: só os ligados com Celita OS da aula; devolve quantos',
        () async {
      final p = _sala();
      addTearDown(p.dispose);
      expect(p.pcsParaEnergia, ['a', 'c']);
      expect(p.motivoSemEnergia, isNull);
      expect(
        await p.energiaNaTurma(AcaoEnergia.reiniciar),
        (enviados: 2, erro: null),
      );
      final e = p.energias.single;
      expect(e.alvos, ['a', 'c']);
      expect(e.acao, AcaoEnergia.reiniciar);
      expect(e.umPc, isFalse);
    });

    test('turma sem alvo: nada sai e vem o motivo', () async {
      final semCelita = FakePairing()
        ..pc('a', nome: 'Ana', ext: _celita, online: false)
        ..pc('d', nome: 'Duda');
      addTearDown(semCelita.dispose);
      const motivo = 'Nenhum computador com Celita OS ligado nesta aula.';
      expect(semCelita.motivoSemEnergia, motivo);
      expect(
        await semCelita.energiaNaTurma(AcaoEnergia.desligar),
        (enviados: 0, erro: motivo),
      );
      expect(semCelita.energias, isEmpty);

      final semAluno = FakePairing()
        ..semTurma = 'Nenhum computador com aluno nesta aula ainda.';
      addTearDown(semAluno.dispose);
      expect(
        semAluno.motivoSemEnergia,
        'Nenhum computador com aluno nesta aula ainda.',
      );
    });

    test('sem internet: o motivo, e ninguém conta como enviado', () async {
      final p = _sala()..erroDaEnergia = kTextoSemInternet;
      addTearDown(p.dispose);
      expect(await p.energiaNoPc('a', AcaoEnergia.desligar), kTextoSemInternet);
      expect(
        await p.energiaNaTurma(AcaoEnergia.desligar),
        (enviados: 0, erro: kTextoSemInternet),
      );
    });

    test('app abrindo (sem transporte): nada é gravado', () async {
      final p = PairingController();
      addTearDown(p.dispose);
      const conectando = 'Ainda conectando — tente de novo.';
      expect(await p.energiaNoPc('a', AcaoEnergia.desligar), conectando);
      expect(await p.enviarEnergia(['a'], AcaoEnergia.desligar), conectando);
      expect(
        await p.energiaNaTurma(AcaoEnergia.desligar),
        (enviados: 0, erro: 'Nenhum computador com Celita OS ligado agora.'),
      );
    });
  });

  group('ação Desligar na tela do computador', () {
    Future<FakePairing> abrir(
      WidgetTester tester,
      FakePairing p,
      String id,
    ) async {
      _telaGrande(tester);
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DevicePage(pairing: p, deviceId: id),
        ),
      );
      return p;
    }

    final botao = find.widgetWithText(BotaoDeAcao, 'Desligar');

    bool habilitado(WidgetTester tester) =>
        tester.widget<BotaoDeAcao>(botao).onPressed != null;

    Future<void> escolher(WidgetTester tester, String acao) async {
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, acao));
      await tester.pumpAndSettle();
    }

    testWidgets('ligado com Celita OS: as três ações, nesta ordem',
        (tester) async {
      await abrir(tester, _sala(), 'a');
      expect(habilitado(tester), isTrue);
      await tester.tap(botao);
      await tester.pumpAndSettle();
      final ys = [
        for (final t in _acoes)
          tester.getTopLeft(find.widgetWithText(ListTile, t)).dy,
      ];
      expect(ys, [...ys]..sort());
    });

    testWidgets('Chromebook: desabilitado, e a dica diz por quê',
        (tester) async {
      await abrir(tester, _sala(), 'd');
      expect(habilitado(tester), isFalse);
      expect(find.byTooltip('Desligar: só com Celita OS'), findsOneWidget);
    });

    testWidgets('Celita desligado: desabilitado', (tester) async {
      await abrir(tester, _sala(), 'b');
      expect(habilitado(tester), isFalse);
    });

    testWidgets('na aula de outro professor: desabilitado, com o motivo no '
        'alto', (tester) async {
      final p = _sala()..outrosProfessores['a'] = 'Prof. Carlos';
      await abrir(tester, p, 'a');
      expect(habilitado(tester), isFalse);
      expect(find.textContaining('na aula de Prof. Carlos'), findsOneWidget);
    });

    testWidgets('Desligar pede confirmação; Cancelar não manda nada',
        (tester) async {
      final p = await abrir(tester, _sala(), 'a');
      await escolher(tester, 'Desligar');
      expect(find.text('Desligar Ana?'), findsOneWidget);
      expect(
        find.text(
          'Desliga na hora. Quem estiver usando perde o que não salvou. Se '
          'estiver instalando uma atualização, termina antes.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(p.energias, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('confirmado: pede só a este computador e avisa',
        (tester) async {
      final p = await abrir(tester, _sala(), 'a');
      await escolher(tester, 'Sair da conta');
      expect(find.text('Sair da conta em Ana?'), findsOneWidget);
      expect(
        find.text(
          'A conta aberta fecha na hora. Quem estiver usando perde o que não '
          'salvou.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sair da conta'));
      await tester.pumpAndSettle();
      final e = p.energias.single;
      expect(e.alvos, ['a']);
      expect(e.acao, AcaoEnergia.encerrar);
      expect(e.umPc, isTrue);
      expect(find.text('Pedido enviado para Ana.'), findsOneWidget);
    });
  });

  group('turma', () {
    testWidgets('o sheet lista as três ações e quantos recebem; confirmado, '
        'manda e conta', (tester) async {
      _telaGrande(tester);
      final p = _sala();
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => mostrarSheetEnergia(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Desligar computadores'), findsOneWidget);
      expect(
        find.text(
          'Vale para os 2 computadores com Celita OS ligados nesta aula.',
        ),
        findsOneWidget,
      );
      for (final t in _acoes) {
        expect(find.widgetWithText(ListTile, t), findsOneWidget, reason: t);
      }

      await tester.tap(find.text('Reiniciar'));
      await tester.pumpAndSettle();
      expect(find.text('Reiniciar 2 computadores?'), findsOneWidget);
      expect(
        find.text(
          'Reiniciam na hora. Quem estiver usando perde o que não salvou. Os '
          'que estiverem instalando uma atualização terminam antes.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reiniciar'));
      await tester.pumpAndSettle();
      final e = p.energias.single;
      expect(e.alvos, ['a', 'c']);
      expect(e.acao, AcaoEnergia.reiniciar);
      expect(e.umPc, isFalse, reason: 'a faixa fica na aba Aula');
      expect(find.text('Pedido enviado para 2 computadores.'), findsOneWidget);
    });

    testWidgets('um computador só: singular; Cancelar não manda',
        (tester) async {
      _telaGrande(tester);
      final p = FakePairing()..pc('a', nome: 'Ana', ext: _celita);
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => mostrarSheetEnergia(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Vale para o computador com Celita OS ligado nesta aula.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();
      expect(find.text('Sair da conta em 1 computador?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(p.energias, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('sem computador com Celita OS ligado: avisa e não abre',
        (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana', ext: _celita, online: false)
        ..pc('d', nome: 'Duda');
      addTearDown(p.dispose);
      await tester.pumpWidget(_comBotao((c) => mostrarSheetEnergia(c, p)));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      expect(
        find.text('Nenhum computador com Celita OS ligado nesta aula.'),
        findsOneWidget,
      );
      expect(find.text('Desligar computadores'), findsNothing);
    });

  });

  group('ações da aula', () {
    const dica = 'Sair da conta, reiniciar ou desligar os computadores';

    Future<FakePairing> abrirAula(WidgetTester tester, double largura) async {
      tester.view.physicalSize = Size(largura * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final p = _sala()..iniciando = false;
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: AulaPage(pairing: p, onIrParaSites: () {}),
        ),
      );
      await tester.pump();
      return p;
    }

    for (final largura in [320.0, 360.0]) {
      testWidgets(
          '${largura.toInt()} dp: oito ações em duas linhas de quatro, sem '
          'estourar; Desligar abre o sheet', (tester) async {
        await abrirAula(tester, largura);
        final acoes = find.byType(BotaoDeAcao);
        expect(acoes, findsNWidgets(8));
        final linhas = {
          for (var i = 0; i < 8; i++) tester.getTopLeft(acoes.at(i)).dy,
        };
        expect(linhas, hasLength(2));

        final botao = find.byTooltip(dica);
        expect(botao, findsOneWidget);
        final semantica = tester.ensureSemantics();
        expect(
          tester.getSemantics(botao),
          isSemantics(tooltip: dica, isButton: true, isEnabled: true),
        );
        semantica.dispose();

        await tester.tap(botao);
        await tester.pumpAndSettle();
        expect(find.text('Desligar computadores'), findsOneWidget);
      });
    }

    testWidgets('do botão até o pedido: escolhe, confirma e avisa',
        (tester) async {
      final p = await abrirAula(tester, 360);
      await tester.tap(find.byTooltip(dica));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Vale para os 2 computadores com Celita OS ligados nesta aula.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Desligar'));
      await tester.pumpAndSettle();
      expect(find.text('Desligar 2 computadores?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Desligar'));
      await tester.pumpAndSettle();
      final e = p.energias.single;
      expect(e.alvos, ['a', 'c']);
      expect(e.acao, AcaoEnergia.desligar);
      expect(e.umPc, isFalse);
      expect(find.text('Pedido enviado para 2 computadores.'), findsOneWidget);
    });
  });
}
