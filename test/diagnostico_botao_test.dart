// "Diagnóstico" nas ações do PC: liga pelo botão; enquanto o PC grava
// (meta/diag no futuro) o botão vira "Gravando" desabilitado, aparece o selo
// com a hora e o ⋮ oferece "Parar o diagnóstico".

import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/device_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

Future<FakePairing> _abrir(WidgetTester tester, {int? diagAte}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = FakePairing()..pc('a', nome: 'Unidade 7', ext: 'celita-1.33.0');
  p.mapa['a']!.diagAte = diagAte;
  addTearDown(p.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: DevicePage(pairing: p, deviceId: 'a'),
    ),
  );
  await tester.pump();
  return p;
}

void main() {
  testWidgets('sem gravação: botão Diagnóstico habilitado e nada no ⋮', (tester) async {
    await _abrir(tester);
    final botao = find.widgetWithText(BotaoDeAcao, 'Diagnóstico');
    expect(botao, findsOneWidget);
    expect(tester.widget<BotaoDeAcao>(botao).onPressed, isNotNull);
    expect(find.text('Gravando'), findsNothing);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    expect(find.text('Diagnóstico de Wi-Fi e da tampa'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    expect(find.text('Parar o diagnóstico'), findsNothing);
    expect(find.text('Gravar diagnóstico'), findsNothing, reason: 'saiu do ⋮');
  });

  testWidgets('gravando: botão desabilitado, selo com a hora e Parar no ⋮', (tester) async {
    final ate = kAgoraTeste + 3 * 3600 * 1000;
    final p = await _abrir(tester, diagAte: ate);
    final hora = DateTime.fromMillisecondsSinceEpoch(ate);
    final hh = '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
    final botao = find.widgetWithText(BotaoDeAcao, 'Gravando');
    expect(botao, findsOneWidget);
    expect(tester.widget<BotaoDeAcao>(botao).onPressed, isNull);
    expect(find.text('Diagnóstico até as $hh'), findsOneWidget);

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parar o diagnóstico'));
    await tester.pumpAndSettle();
    expect(find.text('Parar o diagnóstico'), findsOneWidget, reason: 'confirmação');
    await tester.tap(find.widgetWithText(FilledButton, 'Parar'));
    await tester.pumpAndSettle();
    expect(p.diagnosticos, [('a', 0)]);
  });

  testWidgets('prazo vencido conta como não gravando', (tester) async {
    await _abrir(tester, diagAte: kAgoraTeste - 1000);
    expect(find.widgetWithText(BotaoDeAcao, 'Diagnóstico'), findsOneWidget);
    expect(find.textContaining('Diagnóstico até'), findsNothing);
  });
}
