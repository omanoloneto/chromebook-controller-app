// Smoke test do shell: app sobe com as 4 abas e a Aula em estado "iniciando"
// (controller nunca iniciado = equivalente do antigo autoStart: false).

import 'dart:io';

import 'package:controle_de_aula/src/pairing/pairing_controller.dart';
import 'package:controle_de_aula/src/pairing/prefs_store.dart';
import 'package:controle_de_aula/src/ui/app_shell.dart';
import 'package:controle_de_aula/src/ui/settings_controller.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app sobe e mostra a tela inicial', (WidgetTester tester) async {
    // IO real (temp dir + prefs) precisa rodar FORA da zona FakeAsync do
    // testWidgets — senão o Future nunca completa e o teste trava.
    late final PrefsStore prefs;
    late final Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('cda_widget_');
      prefs = await PrefsStore.load(dir: dir);
    });
    addTearDown(() => dir.delete(recursive: true));
    final pairing = PairingController();
    addTearDown(pairing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: AppShell(pairing: pairing, settings: SettingsController(prefs)),
      ),
    );

    expect(find.text('Controle de Aula'), findsOneWidget); // AppBar da Aula
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // iniciando
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Turmas'), findsWidgets); // destino da barra
    expect(find.text('Ajustes'), findsWidgets);
  });
}
