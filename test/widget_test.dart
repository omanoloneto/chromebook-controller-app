// Teste de fumaça (smoke test) básico do app.
// autoStart: false para não subir o servidor HTTP nem timers durante o teste.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_de_aula/src/ui/home_page.dart';

void main() {
  testWidgets('app sobe e mostra a tela inicial', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomePage(autoStart: false)),
    );

    // O título da AppBar deve aparecer.
    expect(find.text('Controle de Aula'), findsOneWidget);
    // Sem autostart, fica no estado "iniciando" (spinner).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
