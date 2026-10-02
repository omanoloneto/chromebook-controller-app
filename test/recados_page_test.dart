// Recados (SPEC-turma §4.4): as seções na ordem certa, o estado vazio,
// Recusar com motivo, Liberar (uma regra, várias regras, prova) e Baixar.

import 'package:controle_de_aula/src/cloud/conversa.dart';
import 'package:controle_de_aula/src/ui/recados_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

PedidoLiberacao _pedido(String id, String site, {String motivo = ''}) =>
    PedidoLiberacao(
      deviceId: id,
      mid: 'u-$id',
      site: site,
      url: 'https://$site/',
      motivo: motivo,
      bloqueio: 'regra',
      ts: kAgoraTeste - 120000,
    );

Future<FakePairing> _abrir(
  WidgetTester tester,
  void Function(FakePairing p) preparar,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = FakePairing()
    ..pc('a', nome: 'Ana')
    ..pc('b', nome: 'Bruno')
    ..pc('c', nome: 'Caio');
  addTearDown(p.dispose);
  preparar(p);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: RecadosPage(pairing: p),
    ),
  );
  await tester.pump();
  return p;
}

void main() {
  testWidgets('sem nada: estado vazio', (tester) async {
    await _abrir(tester, (_) {});
    expect(find.text('Nenhum recado dos alunos agora.'), findsOneWidget);
  });

  testWidgets('pedidos, mãos e conversas, nesta ordem; silenciado no fim',
      (tester) async {
    await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(
        _pedido('a', 'youtube.com', motivo: 'Vídeo da aula de ciências'),
      );
      p.mapa['b']!.maoEm = kAgoraTeste - 60000;
      p.mapa['c']!
        ..chat.add(
          msg('1', AutorChat.aluno, 'Terminei a atividade', min: -3),
        )
        ..naoLidas = 1;
      p.mapa['a']!.chat.add(
        msg(
          '2',
          AutorChat.professor,
          'Pode abrir',
          min: -5,
          estado: EstadoBalao.entregue,
        ),
      );
      p.silenciados = ['b'];
    });
    final titulos = [
      'Pedidos de liberação (1)',
      'Mãos levantadas (1)',
      'Conversas (2)',
    ];
    final ys = [for (final t in titulos) tester.getTopLeft(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.text('Ana · 10:40'), findsOneWidget);
    expect(find.text('youtube.com'), findsOneWidget);
    expect(find.text('“Vídeo da aula de ciências”'), findsOneWidget);
    expect(find.text('Bruno levantou a mão · 10:41'), findsOneWidget);
    // Conversa mais recente primeiro; a do professor tem "Você: ".
    final caio = tester.getTopLeft(find.text('Terminei a atividade')).dy;
    final ana = tester.getTopLeft(find.text('Você: Pode abrir')).dy;
    expect(caio, lessThan(ana));
    expect(find.byType(Badge), findsOneWidget);
    final silencio = tester.getTopLeft(find.text(kTextoSilenciado)).dy;
    expect(silencio, greaterThan(ana));
  });

  testWidgets('Recusar com motivo manda o motivo ao aluno', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'jogos.com'));
    });
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    expect(find.text('Recusar o pedido?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Depois da prova.  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Recusar'));
    await tester.pumpAndSettle();
    expect(p.recusados, hasLength(1));
    expect(p.recusados.single.$1.site, 'jogos.com');
    expect(p.recusados.single.$2, 'Depois da prova.');
    expect(find.text('Pedido recusado.'), findsOneWidget);
    expect(find.text('jogos.com'), findsNothing);
  });

  testWidgets('toque duplo em Recusar ou Liberar abre um diálogo só',
      (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'youtube.com'));
      p.padroes = ['youtube.com', '*.googlevideo.com'];
    });
    await tester.tap(find.text('Recusar'));
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    expect(find.text('Recusar o pedido?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(p.recusados, isEmpty);

    await tester.tap(find.text('Liberar'));
    await tester.tap(find.text('Liberar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Liberar para Ana'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(p.liberados, isEmpty);
    // Cancelado: os botões voltam.
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Recusar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Recusar sem motivo manda null; Cancelar não recusa',
      (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'jogos.com'));
    });
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(p.recusados, isEmpty);
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Recusar'));
    await tester.pumpAndSettle();
    expect(p.recusados.single.$2, isNull);
  });

  testWidgets('Liberar com uma regra: sem pergunta', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'youtube.com'));
      p.padroes = ['youtube.com'];
    });
    await tester.tap(find.text('Liberar'));
    await tester.pumpAndSettle();
    expect(p.liberados.single.$2, ['youtube.com']);
    expect(find.text('youtube.com liberado para Ana.'), findsOneWidget);
  });

  testWidgets('Liberar com várias regras pergunta antes', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'youtube.com'));
      p.padroes = ['youtube.com', '*.googlevideo.com'];
    });
    await tester.tap(find.text('Liberar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Liberar para Ana: youtube.com, *.googlevideo.com?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(p.liberados, isEmpty);
    await tester.tap(find.text('Liberar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Liberar').last);
    await tester.pumpAndSettle();
    expect(p.liberados.single.$2, ['youtube.com', '*.googlevideo.com']);
  });

  testWidgets('Liberar na prova não mexe nas regras', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.pedidos.add(_pedido('a', 'wikipedia.org'));
      p.emProva.add('a');
      p.padroes = ['a.com', 'b.com']; // não deve ser usado
    });
    await tester.tap(find.text('Liberar'));
    await tester.pumpAndSettle();
    expect(p.liberados.single.$2, isNull);
    expect(find.textContaining('Liberar para'), findsNothing);
  });

  testWidgets('Baixar a mão', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['b']!.maoEm = kAgoraTeste - 60000;
    });
    await tester.tap(find.text('Baixar'));
    await tester.pump();
    expect(p.maosBaixadas, ['b']);
    expect(find.text('Nenhum recado dos alunos agora.'), findsOneWidget);
  });
}
