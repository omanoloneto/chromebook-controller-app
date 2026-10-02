// Faixas de confirmação (SPEC-turma §6.3, §7.4, §8.4): textos e plural, a
// confirmação refeita do estado (app reiniciado) e o banner que vira
// SnackBar uma vez só.

import 'package:controle_de_aula/src/cloud/entrega.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/ui/faixa_entrega.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

final _t0 = DateTime(2026, 10, 2, 10, 42);

const _travou = EstadoAplicado(rev: 3, on: true);

Entrega _comando(Map<String, bool> online) {
  final e = Entrega(tipo: TipoEntrega.comando, enviadoEm: _t0);
  online.forEach(
    (id, on) => e.adicionar(id, cmdId: 'c-$id', online: on, suportaTurma: true),
  );
  return e;
}

/// O SnackBar de 4 s sai sozinho (o relógio dele só começa depois da
/// animação de entrada).
Future<void> _esperarSnackSumir(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

Widget _app(FakePairing p, Widget filho) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Column(children: [filho, const Spacer()])),
    );

void main() {
  group('textos e plural', () {
    test('comando: andamento, todos e parcial com plural', () {
      final e = _comando({'a': true, 'b': true, 'c': false, 'd': false});
      expect(textoEntrega(e), 'Enviando… 0 de 4');
      e.aoAck('a', 'c-a', ok: true);
      e.aoAck('b', 'c-b', ok: true);
      expect(
        textoEntrega(e),
        '✓ 2 de 4 receberam · 2 desligados (recebem quando ligarem)',
      );
      final um = _comando({'a': true, 'b': false});
      um.aoAck('a', 'c-a', ok: true);
      expect(
        textoEntrega(um),
        '✓ 1 de 2 receberam · 1 desligado (recebem quando ligarem)',
      );
      final todos = _comando({'a': true});
      todos.aoAck('a', 'c-a', ok: true);
      expect(textoEntrega(todos), '✓ Todos receberam (1)');
    });

    test('trava refeita do estado: 1 não travou × 2 não travaram', () {
      final um = entregaDoEstado(TipoEntrega.trava, [
        const PcNoEstado(
          deviceId: 'a',
          online: true,
          suportaTurma: true,
          aplicado: _travou,
        ),
        const PcNoEstado(deviceId: 'b', online: true, suportaTurma: true),
      ]);
      expect(textoTrava(um), 'Telas travadas: 1 de 2 · 1 não travou');
      final dois = entregaDoEstado(TipoEntrega.trava, [
        const PcNoEstado(deviceId: 'a', online: true, suportaTurma: true),
        const PcNoEstado(deviceId: 'b', online: true, suportaTurma: true),
      ]);
      expect(textoTrava(dois), 'Telas travadas: 0 de 2 · 2 não travaram');
      expect(
        textoTrava(dois, desde: DateTime(2026, 10, 2, 9, 5)),
        'Telas travadas: 0 de 2 · 2 não travaram · desde 09:05',
      );
    });

    test('estado: desligado, versão antiga, ninguém logado e navegador', () {
      final e = entregaDoEstado(TipoEntrega.trava, [
        const PcNoEstado(
          deviceId: 'ok',
          online: true,
          suportaTurma: true,
          aplicado: _travou,
        ),
        // Desligado conta como desligado, mesmo com `aplicado` velho.
        const PcNoEstado(
          deviceId: 'off',
          online: false,
          suportaTurma: true,
          aplicado: _travou,
        ),
        const PcNoEstado(deviceId: 'velho', online: true, suportaTurma: false),
        const PcNoEstado(
          deviceId: 'z',
          online: true,
          suportaTurma: true,
          aplicado: EstadoAplicado(rev: 3, on: true, erro: 'sem_sessao'),
        ),
        // Aplicado "desligado": ainda não travou.
        const PcNoEstado(
          deviceId: 'n',
          online: true,
          suportaTurma: true,
          aplicado: EstadoAplicado(rev: 3, on: false),
        ),
      ]);
      expect(e.resolvida, isTrue);
      expect(
        textoTrava(e),
        'Telas travadas: 1 de 5 · 1 desligado · 1 com versão antiga · '
        '1 sem ninguém logado · 1 não travou',
      );
    });

    test('prova refeita do estado: plural de "não entrou" e navegador', () {
      final e = entregaDoEstado(TipoEntrega.prova, [
        const PcNoEstado(
          deviceId: 'a',
          online: true,
          suportaTurma: true,
          aplicado: EstadoAplicado(rev: 1, on: true),
        ),
        const PcNoEstado(
          deviceId: 'b',
          online: true,
          suportaTurma: true,
          aplicado: EstadoAplicado(rev: 1, on: true, erro: 'navegador_antigo'),
        ),
        const PcNoEstado(deviceId: 'c', online: true, suportaTurma: true),
        const PcNoEstado(deviceId: 'd', online: true, suportaTurma: true),
      ]);
      expect(
        textoProva(e),
        'Modo prova: 1 de 4 · 1 com o navegador desatualizado · '
        '2 não entraram',
      );
    });

    test('estado vazio não tem faixa (total 0)', () {
      expect(entregaDoEstado(TipoEntrega.trava, const []).total, 0);
    });
  });

  group('FaixaEntrega (banner → SnackBar)', () {
    testWidgets('enviando mostra o banner; resolvido vira SnackBar uma vez',
        (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno', online: false);
      addTearDown(p.dispose);
      final e = _comando({'a': true, 'b': false});
      p.entregaFake = e;
      await tester.pumpWidget(_app(p, FaixaEntrega(pairing: p)));
      // A faixa só acompanha o envio quando ouve uma mudança.
      p.avisar();
      await tester.pump();
      expect(find.text('Enviando… 0 de 2'), findsOneWidget);
      expect(find.text('Detalhes'), findsOneWidget);

      e.aoAck('a', 'c-a', ok: true);
      p.avisar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Enviando… 0 de 2'), findsNothing);
      const fim = '✓ 1 de 2 receberam · 1 desligado (recebem quando ligarem)';
      expect(find.text(fim), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Detalhes'), findsOneWidget);

      // Outra mudança qualquer não repete o aviso.
      p.avisar();
      await _esperarSnackSumir(tester);
      expect(find.text(fim), findsNothing);
      p.avisar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Detalhes lista quem não recebeu primeiro', (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno', online: false);
      addTearDown(p.dispose);
      final e = _comando({'a': true, 'b': false});
      p.entregaFake = e;
      await tester.pumpWidget(_app(p, FaixaEntrega(pairing: p)));
      p.avisar();
      await tester.pump();
      await tester.tap(find.text('Detalhes'));
      // Há spinner na tela (pumpAndSettle nunca assentaria).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Quem recebeu'), findsOneWidget);
      final bruno = tester.getTopLeft(
        find.text('Bruno — Desligado — recebe quando ligar'),
      );
      final ana = tester.getTopLeft(find.text('Ana — Enviando…'));
      expect(bruno.dy, lessThan(ana.dy));
    });

    testWidgets('envio novo com todos desligados vira SnackBar na hora',
        (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana', online: false)
        ..pc('b', nome: 'Bruno', online: false);
      addTearDown(p.dispose);
      await tester.pumpWidget(_app(p, FaixaEntrega(pairing: p)));
      p.entregaFake = _comando({'a': false, 'b': false});
      p.avisar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MaterialBanner), findsNothing);
      expect(
        find.text('✓ 0 de 2 receberam · 2 desligados (recebem quando ligarem)'),
        findsOneWidget,
      );
      await _esperarSnackSumir(tester);
    });

    testWidgets('envio para um PC desligado avisa na tela dele',
        (tester) async {
      final p = FakePairing()..pc('a', nome: 'Ana', online: false);
      addTearDown(p.dispose);
      await tester.pumpWidget(
        _app(p, FaixaEntrega(pairing: p, deviceId: 'a', cartao: true)),
      );
      p
        ..entregaFake = _comando({'a': false})
        ..entregaUmPcFake = 'a';
      p.avisar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Ana está desligado — recebe quando ligar'),
        findsOneWidget,
      );
      await _esperarSnackSumir(tester);
    });

    testWidgets('envio já resolvido ao abrir a tela não vira SnackBar',
        (tester) async {
      final p = FakePairing()..pc('a', nome: 'Ana');
      addTearDown(p.dispose);
      final e = _comando({'a': true})..aoAck('a', 'c-a', ok: true);
      p.entregaFake = e;
      await tester.pumpWidget(_app(p, FaixaEntrega(pairing: p)));
      p.avisar();
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('envio para um PC só aparece na tela dele', (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno');
      addTearDown(p.dispose);
      p
        ..entregaFake = _comando({'a': true})
        ..entregaUmPcFake = 'a';
      await tester.pumpWidget(
        _app(
          p,
          Column(
            children: [
              FaixaEntrega(pairing: p), // aba Aula
              FaixaEntrega(pairing: p, deviceId: 'b'),
              FaixaEntrega(pairing: p, deviceId: 'a', cartao: true),
            ],
          ),
        ),
      );
      p.avisar();
      await tester.pump();
      expect(find.text('Enviando para Ana…'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsOneWidget);
    });
  });

  group('FaixaEstadoTurma', () {
    testWidgets('trava ligada é refeita do estado (app reiniciado)',
        (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno', online: false)
        ..pc('c', nome: 'Caio')
        ..pc('d', nome: 'Duda');
      addTearDown(p.dispose);
      p.mapa['a']!.aplicado = const Aplicado(trava: _travou);
      p
        ..travados.addAll(['a', 'b', 'c'])
        ..travaLigadaFake = true;
      await tester.pumpWidget(
        _app(p, FaixaEstadoTurma(pairing: p, tipo: TipoEntrega.trava)),
      );
      expect(
        find.text('Telas travadas: 1 de 3 · 1 desligado · 1 não travou'),
        findsOneWidget,
      );
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('Telas travadas'), findsOneWidget); // título do sheet
      expect(find.text('Caio — Não travou'), findsOneWidget);
      expect(find.text('Ana — Tela travada ✓'), findsOneWidget);
    });

    testWidgets('durante a confirmação mostra o andamento', (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno');
      addTearDown(p.dispose);
      final e = Entrega(tipo: TipoEntrega.trava, enviadoEm: _t0)
        ..adicionar('a', online: true, suportaTurma: true, comandoNovo: true)
        ..adicionar('b', online: true, suportaTurma: true, comandoNovo: true);
      e.aoAplicado('a', const Aplicado(trava: _travou));
      p
        ..entregaTravaFake = e
        ..travaLigadaFake = true;
      await tester.pumpWidget(
        _app(p, FaixaEstadoTurma(pairing: p, tipo: TipoEntrega.trava)),
      );
      expect(find.text('Travando… 1 de 2'), findsOneWidget);
    });

    testWidgets('destravar resolvido vira SnackBar; faixa some',
        (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno');
      addTearDown(p.dispose);
      final e = Entrega(tipo: TipoEntrega.trava, enviadoEm: _t0, alvoOn: false)
        ..adicionar('a', online: true, suportaTurma: true, comandoNovo: true)
        ..adicionar('b', online: true, suportaTurma: true, comandoNovo: true);
      p.entregaTravaFake = e;
      await tester.pumpWidget(
        _app(p, FaixaEstadoTurma(pairing: p, tipo: TipoEntrega.trava)),
      );
      p.avisar();
      await tester.pump();
      expect(find.text('Destravando… 0 de 2'), findsOneWidget);
      const off = EstadoAplicado(rev: 4, on: false);
      e
        ..aoAplicado('a', const Aplicado(trava: off))
        ..aoAplicado('b', const Aplicado(trava: off));
      p.avisar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Telas destravadas: 2 de 2'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Destravando… 0 de 2'), findsNothing);
      await _esperarSnackSumir(tester);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('prova ligada: "Modo prova: 2 de 2"', (tester) async {
      final p = FakePairing()
        ..pc('a', nome: 'Ana')
        ..pc('b', nome: 'Bruno');
      addTearDown(p.dispose);
      const on = EstadoAplicado(rev: 1, on: true);
      p.mapa['a']!.aplicado = const Aplicado(prova: on);
      p.mapa['b']!.aplicado = const Aplicado(prova: on);
      p
        ..emProva.addAll(['a', 'b'])
        ..provaLigadaFake = true;
      await tester.pumpWidget(
        _app(p, FaixaEstadoTurma(pairing: p, tipo: TipoEntrega.prova)),
      );
      expect(find.text('Modo prova: 2 de 2'), findsOneWidget);
    });

    testWidgets('nada ligado: nenhuma faixa', (tester) async {
      final p = FakePairing()..pc('a', nome: 'Ana');
      addTearDown(p.dispose);
      await tester.pumpWidget(
        _app(p, FaixaEstadoTurma(pairing: p, tipo: TipoEntrega.trava)),
      );
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
