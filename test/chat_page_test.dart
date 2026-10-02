// Conversa com o aluno (SPEC-turma §3.6): a legenda de cada estado do balão
// do professor, o texto da rede mostrado como texto puro, o envio, a mão
// levantada e o PC reservado por outro professor.

import 'package:controle_de_aula/src/cloud/conversa.dart';
import 'package:controle_de_aula/src/ui/chat_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

Widget _bolha(ChatItem item, {String ext = '0.7.0'}) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: BolhaDoChat(
            item: item,
            legenda: item.autor == AutorChat.professor
                ? legendaDoBalao(item, ext: ext)
                : '',
          ),
        ),
      ),
    );

Future<FakePairing> _abrir(
  WidgetTester tester,
  void Function(FakePairing p) preparar,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = FakePairing()..pc('a', nome: 'Ana Souza');
  addTearDown(p.dispose);
  preparar(p);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChatPage(pairing: p, deviceId: 'a'),
    ),
  );
  await tester.pump();
  return p;
}

void main() {
  group('legenda do balão do professor', () {
    final casos = <(EstadoBalao, String)>[
      (EstadoBalao.enviando, '10:42 · Enviando…'),
      (EstadoBalao.entregue, '10:42 · ✓ Entregue'),
      (EstadoBalao.aguardando, '10:42 · Aguardando (PC desligado)'),
      (EstadoBalao.ninguemLogado, '10:42 · Ninguém logado — não entregue'),
      (EstadoBalao.semResposta, '10:42 · Não respondeu a tempo'),
    ];
    for (final (estado, rodape) in casos) {
      testWidgets('$estado → "$rodape"', (tester) async {
        await tester.pumpWidget(
          _bolha(msg('m', AutorChat.professor, 'Oi', estado: estado)),
        );
        expect(find.text(rodape), findsOneWidget);
      });
    }

    testWidgets('falha neste celular: texto de sem internet, em vermelho',
        (tester) async {
      final item = msg('m', AutorChat.professor, 'Oi', estado: EstadoBalao.erro)
        ..codigoErro = kErroEnvioLocal;
      await tester.pumpWidget(_bolha(item));
      const rodape = '10:42 · Sem conexão com a internet. Tente de novo.';
      expect(find.text(rodape), findsOneWidget);
      final ctx = tester.element(find.text(rodape));
      expect(
        tester.widget<Text>(find.text(rodape)).style?.color,
        Theme.of(ctx).colorScheme.error,
      );
    });

    testWidgets('relógio só enquanto envia ou aguarda', (tester) async {
      await tester.pumpWidget(
        _bolha(
          msg('m', AutorChat.professor, 'Oi', estado: EstadoBalao.aguardando),
        ),
      );
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      await tester.pumpWidget(
        _bolha(
          msg('m', AutorChat.professor, 'Oi', estado: EstadoBalao.entregue),
        ),
      );
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('mensagem para a turma ganha "para a turma"', (tester) async {
      await tester.pumpWidget(
        _bolha(
          msg(
            'm',
            AutorChat.professor,
            'Abram o livro',
            estado: EstadoBalao.entregue,
            paraTurma: true,
          ),
        ),
      );
      expect(find.text('10:42 · ✓ Entregue · para a turma'), findsOneWidget);
    });

    testWidgets('aluno: só a hora embaixo', (tester) async {
      await tester.pumpWidget(_bolha(msg('m', AutorChat.aluno, 'Oi')));
      expect(find.text('10:42'), findsOneWidget);
    });
  });

  testWidgets('texto que vem da rede aparece como texto, nunca markup',
      (tester) async {
    const perigoso = '<b>oi</b> [link](https://exemplo.com) **negrito**';
    await _abrir(tester, (p) {
      p.mapa['a']!.chat.add(msg('x', AutorChat.aluno, perigoso));
    });
    final achado = find.text(perigoso);
    expect(achado, findsOneWidget);
    final t = tester.widget<Text>(achado);
    expect(t.data, perigoso);
    expect(t.textSpan, isNull);
    expect(find.text('oi'), findsNothing);
  });

  testWidgets('abrir zera as não lidas e mostra a conversa em ordem',
      (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!
        ..naoLidas = 2
        ..chat.addAll([
          msg('1', AutorChat.aluno, 'Professora, posso abrir o site?'),
          msg(
            '2',
            AutorChat.professor,
            'Pode sim',
            min: 1,
            estado: EstadoBalao.entregue,
          ),
        ]);
    });
    expect(p.conversasAbertas, ['a']);
    expect(p.mapa['a']!.naoLidas, 0);
    final aluno =
        tester.getCenter(find.text('Professora, posso abrir o site?'));
    final prof = tester.getCenter(find.text('Pode sim'));
    expect(aluno.dy, lessThan(prof.dy)); // mais nova embaixo
    expect(aluno.dx, lessThan(prof.dx)); // aluno à esquerda
    expect(find.text('online'), findsOneWidget);
  });

  testWidgets('conversa vazia explica o que acontece', (tester) async {
    await _abrir(tester, (_) {});
    expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);
    expect(find.text('Escreva uma mensagem…'), findsOneWidget);
  });

  testWidgets('Enviar manda o texto e limpa o campo', (tester) async {
    final p = await _abrir(tester, (_) {});
    final enviar = find.byTooltip('Enviar');
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  Bom trabalho!  ');
    await tester.pump();
    await tester.tap(enviar);
    await tester.pump();
    expect(p.chatsEnviados, [('a', '  Bom trabalho!  ')]);
    expect(find.text('Bom trabalho!'), findsOneWidget); // o balão
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('recusado antes de virar balão: o texto fica e vira SnackBar',
      (tester) async {
    final p = await _abrir(tester, (p) => p.erroDoChat = 'Escreva a mensagem.');
    await tester.enterText(find.byType(TextField), 'Oi');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    expect(p.chatsEnviados, hasLength(1));
    expect(find.text('Escreva a mensagem.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Oi',
    );
  });

  testWidgets('mão levantada: linha no topo com "Baixar"', (tester) async {
    final p = await _abrir(tester, (p) {
      p.mapa['a']!.maoEm = kAgoraTeste - 60000;
    });
    expect(find.text('Ana Souza levantou a mão às 10:41'), findsOneWidget);
    await tester.tap(find.text('Baixar'));
    await tester.pump();
    expect(p.maosBaixadas, ['a']);
    expect(find.textContaining('levantou a mão'), findsNothing);
  });

  testWidgets('PC na aula de outro professor: sem campo nem "Baixar"',
      (tester) async {
    await _abrir(tester, (p) {
      p.outrosProfessores['a'] = 'Rita';
      p.mapa['a']!.maoEm = kAgoraTeste - 60000;
    });
    expect(find.text('Este computador está na aula de Rita.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Baixar'), findsNothing);
    // Sem campo, a conversa vazia não manda escrever.
    expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);
    expect(find.textContaining('Escreva para'), findsNothing);
  });

  testWidgets(
      'aberta por notificação antes de o PC carregar: abre (zera e baixa a '
      'mão) quando ele chega', (tester) async {
    final p = FakePairing();
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ChatPage(pairing: p, deviceId: 'a'),
      ),
    );
    await tester.pump();
    expect(p.conversasAbertas, isEmpty);

    p.pc('a', nome: 'Ana Souza')
      ..naoLidas = 1
      ..maoEm = kAgoraTeste - 60000;
    p.avisar();
    await tester.pump();
    expect(p.conversasAbertas, ['a']);
    expect(p.mapa['a']!.naoLidas, 0);
    // Uma vez só.
    p.avisar();
    await tester.pump();
    expect(p.conversasAbertas, ['a']);
  });

  testWidgets('PC com versão antiga avisa que o aluno não responde',
      (tester) async {
    await _abrir(tester, (p) => p.mapa['a']!.versaoExt = '0.6.2');
    expect(
      find.text(
        'Este computador tem uma versão antiga: o aluno vê suas mensagens, '
        'mas não consegue responder.',
      ),
      findsOneWidget,
    );
  });

  test('iniciais do avatar', () {
    expect(iniciaisDe('Ana Paula Souza'), 'AS');
    expect(iniciaisDe('Pedro'), 'PE');
    expect(iniciaisDe('  '), '?');
    expect(iniciaisDe('Élio árias'), 'ÉÁ');
  });
}
