// Telas abertas por cima da shell (sem a barra de abas embaixo): o fim da
// lista precisa respeitar a barra de navegação do Android, senão o último
// item fica escondido atrás dela.

import 'package:controle_de_aula/src/ui/componentes.dart';
import 'package:controle_de_aula/src/ui/recados_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

const _barra = 48.0;

Future<void> _abrir(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(bottom: _barra * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );
  await tester.pump();
}

void main() {
  testWidgets('recuoDaLista soma a barra de navegação ao espaço pedido',
      (tester) async {
    late EdgeInsets recuo;
    await _abrir(
      tester,
      Builder(builder: (ctx) {
        recuo = recuoDaLista(ctx, topo: 4, fundo: 24);
        return const SizedBox();
      }),
    );
    expect(recuo, const EdgeInsets.only(top: 4, bottom: 24 + _barra));
  });

  testWidgets('Recados: a lista termina acima da barra de navegação',
      (tester) async {
    final p = FakePairing()..pc('a', nome: 'Ana');
    addTearDown(p.dispose);
    p.mapa['a']!.maoEm = kAgoraTeste - 60000;
    await _abrir(tester, RecadosPage(pairing: p));
    final lista = tester.widget<ListView>(find.byType(ListView));
    expect(lista.padding!.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(_barra));
  });
}
