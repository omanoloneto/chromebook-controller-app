// "Saúde da frota": quem precisa de atenção vem primeiro, com os motivos, os
// números do PC e a ação que resolve.

import 'package:controle_de_aula/src/cloud/pc_health.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/fleet_health_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

Future<void> _abrir(WidgetTester tester, FakePairing p) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  addTearDown(p.dispose);
  await tester.pumpWidget(
    MaterialApp(theme: buildTheme(Brightness.light), home: FleetHealthPage(pairing: p)),
  );
  await tester.pump();
}

FakePairing _frota() {
  final p = FakePairing()..versaoPublicada = '1.38.0';
  final agora = DateTime.fromMillisecondsSinceEpoch(kAgoraTeste);
  p.pc('ok', nome: 'Unidade 2', ext: 'celita-0.23.0')
    ..versaoOs = '1.38.0'
    ..lastSeen = agora
    ..healthAt = DateTime(2026, 10, 2, 8, 5)
    ..health = const PcHealth(
      firmware: 'MrChromebox-2609.3',
      model: 'Bluebird',
      batteryHealth: 88,
      batteryCycles: 210,
      root: DiskVolume(freeGb: 12.4, totalGb: 28),
      storageWear: 'normal',
    );
  p.pc('reinicia', nome: 'Unidade 10', ext: 'celita-0.23.0')
    ..versaoOs = '1.38.0'
    ..lastSeen = agora
    ..health = const PcHealth(
      rebootPending: true,
      batteryHealth: 41,
      wrongKeyNetworks: ['Academico'],
    );
  p.pc('velho', nome: 'Unidade 7', ext: 'celita-0.22.0')
    ..versaoOs = '1.35.0'
    ..lastSeen = agora;
  p.pc('chromeos', nome: 'Chromebook da sala', ext: '0.7.0');
  return p;
}

void main() {
  testWidgets('sem PC com Celita OS mostra o estado vazio', (tester) async {
    final p = FakePairing()..pc('a', ext: '0.7.0');
    await _abrir(tester, p);
    expect(find.byType(EstadoVazio), findsOneWidget);
    expect(find.text('Nenhum computador com Celita OS'), findsOneWidget);
  });

  testWidgets('atenção primeiro, com os motivos; ChromeOS fica de fora', (tester) async {
    await _abrir(tester, _frota());
    expect(find.text('Precisa de atenção (2)'), findsOneWidget);
    expect(find.text('Sem problemas (1)'), findsOneWidget);
    expect(find.text('Chromebook da sala'), findsNothing);
    final nomes = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile)).map(
          (t) => (t.title as Text).data,
        );
    expect(nomes, ['Unidade 7', 'Unidade 10', 'Unidade 2']);
    expect(find.text('Celita OS antigo (1.35.0)'), findsOneWidget);
    expect(
      find.text(
        'Falta reiniciar para terminar a atualização · Senha errada do Wi-Fi Academico · '
        'Bateria gasta (41% da capacidade)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('detalhes do PC saudável: bateria, disco, firmware e data', (tester) async {
    await _abrir(tester, _frota());
    await tester.tap(find.text('Unidade 2'));
    await tester.pumpAndSettle();
    expect(find.text('Celita OS 1.38.0'), findsOneWidget);
    expect(find.text('Modelo Bluebird'), findsOneWidget);
    expect(find.text('Firmware MrChromebox-2609.3'), findsOneWidget);
    expect(find.text('Bateria: 88% da capacidade, 210 ciclos'), findsOneWidget);
    expect(find.text('Sistema: 12 GB livres de 28 GB'), findsOneWidget);
    expect(find.text('Informado em 02/10 às 08:05'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reiniciar'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Atualizar'), findsNothing);
  });

  testWidgets('falta reiniciar: o botão confirma e reinicia o PC', (tester) async {
    final p = _frota();
    await _abrir(tester, p);
    await tester.tap(find.text('Unidade 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reiniciar'));
    await tester.pumpAndSettle();
    expect(find.text('Reiniciar Unidade 10?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reiniciar').last);
    await tester.pumpAndSettle();
    expect(p.energias.single.alvos, ['reinicia']);
    expect(p.energias.single.acao, AcaoEnergia.reiniciar);
  });

  testWidgets('Celita antigo: o botão pede a atualização', (tester) async {
    final p = _frota();
    await _abrir(tester, p);
    await tester.tap(find.text('Unidade 7'));
    await tester.pumpAndSettle();
    expect(
      find.text('Este Celita OS ainda não informa bateria, disco e firmware.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Atualizar'));
    await tester.pump();
    expect(p.atualizados, ['velho']);
    expect(
      find.text('Unidade 7 vai baixar e instalar a atualização sozinho.'),
      findsOneWidget,
    );
  });

  testWidgets('PC desligado não oferece ação', (tester) async {
    final p = _frota();
    p.desligados.addAll(['reinicia', 'velho']);
    await _abrir(tester, p);
    await tester.tap(find.text('Unidade 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unidade 7'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Reiniciar'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Atualizar'), findsNothing);
  });
}
