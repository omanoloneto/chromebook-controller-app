// Spinner de espera (foto/tela/histórico): fecha só a própria rota. O voltar
// do Android e o toque numa notificação podem tirá-lo antes.

import 'dart:async';

import 'package:controle_de_aula/src/ui/device_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext paginaCtx;
  late Completer<String> tarefa;
  String? resultado;
  bool? naFrente;

  Future<void> abrirPagina(WidgetTester tester) async {
    tarefa = Completer<String>();
    resultado = null;
    naFrente = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/pc'),
                builder: (c) {
                  paginaCtx = c;
                  return const Scaffold(body: Text('pagina'));
                },
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    unawaited(() async {
      resultado = await esperarComSpinner(paginaCtx, 'Buscando…', tarefa.future);
      naFrente = paginaCtx.mounted && continuaNaFrente(paginaCtx);
    }());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Buscando…'), findsOneWidget);
  }

  testWidgets('fecha o spinner e a página continua', (tester) async {
    await abrirPagina(tester);
    tarefa.complete('ok');
    await tester.pumpAndSettle();
    expect(resultado, 'ok');
    expect(naFrente, isTrue);
    expect(find.text('Buscando…'), findsNothing);
    expect(find.text('pagina'), findsOneWidget);
  });

  testWidgets('voltar do Android fechou o spinner: a página não fecha', (tester) async {
    await abrirPagina(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Buscando…'), findsNothing);
    tarefa.complete('ok');
    await tester.pumpAndSettle();
    expect(find.text('pagina'), findsOneWidget);
    expect(naFrente, isTrue);
  });

  testWidgets('toque na notificação (popUntil) tirou o spinner: a página não fecha',
      (tester) async {
    await abrirPagina(tester);
    Navigator.of(paginaCtx).popUntil((r) => r.settings.name == '/pc' || r.isFirst);
    await tester.pumpAndSettle();
    tarefa.complete('ok');
    await tester.pumpAndSettle();
    expect(find.text('pagina'), findsOneWidget);
  });

  testWidgets('outra tela abriu por cima: não está mais na frente', (tester) async {
    await abrirPagina(tester);
    Navigator.of(paginaCtx).push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('outra'))),
    );
    await tester.pumpAndSettle();
    tarefa.complete('ok');
    await tester.pumpAndSettle();
    expect(find.text('outra'), findsOneWidget);
    expect(naFrente, isFalse);
  });
}
