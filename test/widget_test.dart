// Teste de fumaça (smoke test) básico do app.
// Garante que o app sobe e a tela inicial renderiza.

import 'package:flutter_test/flutter_test.dart';

import 'package:controle_de_aula/main.dart';

void main() {
  testWidgets('app sobe e mostra a tela inicial', (WidgetTester tester) async {
    await tester.pumpWidget(const ControleDeAulaApp());

    // O título da AppBar deve aparecer.
    expect(find.text('Controle de Aula'), findsOneWidget);
    // O botão de parear deve existir.
    expect(find.text('Parear'), findsOneWidget);
  });
}
