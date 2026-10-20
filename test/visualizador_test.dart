// Tela cheia de foto e vídeo: toque duplo dá e desfaz o zoom, um toque
// esconde a barra, salvar avisa, excluir pede confirmação e fecha, a ação a
// mais fecha e roda; o vídeo deitado vira tela cheia sem a barra do sistema.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:controle_de_aula/src/ui/visualizador.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// PNG de 1×1: basta uma imagem que abra.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void _celular(WidgetTester tester, {bool deitado = false}) {
  tester.view.physicalSize = deitado ? const Size(2340, 1080) : const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => MaterialApp(theme: buildTheme(Brightness.light), home: home);

/// Opacidade da barra de cima (a do título).
double _barra(WidgetTester tester, String titulo) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: find.text(titulo), matching: find.byType(AnimatedOpacity)).first,
    )
    .opacity;

Future<void> _toqueDuplo(WidgetTester tester, Offset ponto) async {
  await tester.tapAt(ponto);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(ponto);
  await tester.pumpAndSettle();
}

class _VideoFalso extends VideoPlayerPlatform {
  final List<String> chamadas = [];
  final Map<int, StreamController<VideoEvent>> _eventos = {};
  var _proximo = 1;

  int _novo() {
    final id = _proximo++;
    late final StreamController<VideoEvent> c;
    c = StreamController<VideoEvent>(
      onListen: () => c.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 42),
          size: const Size(1280, 720),
        ),
      ),
    );
    _eventos[id] = c;
    return id;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _novo();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _novo();

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _eventos[playerId]!.stream;

  @override
  Future<void> play(int playerId) async => chamadas.add('play');

  @override
  Future<void> pause(int playerId) async => chamadas.add('pause');

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.blueGrey);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> dispose(int playerId) async => _eventos.remove(playerId)?.close();
}

void main() {
  group('foto', () {
    testWidgets('título e legenda; toque duplo dá e desfaz o zoom; um toque esconde a barra',
        (tester) async {
      _celular(tester);
      await tester.pumpWidget(
        _app(
          VisualizadorDeImagem(
            imagem: MemoryImage(_png),
            titulo: 'Unidade 3',
            legenda: 'Entrou às 07:42',
            onSalvar: () async => null,
          ),
        ),
      );
      expect(find.text('Unidade 3'), findsOneWidget);
      expect(find.text('Entrou às 07:42'), findsOneWidget);

      final zoom = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
      final centro = tester.getCenter(find.byType(InteractiveViewer));
      await _toqueDuplo(tester, centro);
      expect(zoom.value.getMaxScaleOnAxis(), greaterThan(2));
      await _toqueDuplo(tester, centro);
      expect(zoom.value.getMaxScaleOnAxis(), closeTo(1, 0.01));

      expect(_barra(tester, 'Unidade 3'), 1);
      await tester.tapAt(centro);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_barra(tester, 'Unidade 3'), 0);
      await tester.tapAt(centro);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_barra(tester, 'Unidade 3'), 1);
    });

    testWidgets('Salvar no celular chama quem salva e avisa; o erro aparece', (tester) async {
      _celular(tester);
      var salvou = 0;
      String? erro;
      await tester.pumpWidget(
        _app(
          VisualizadorDeImagem(
            imagem: MemoryImage(_png),
            titulo: 'Foto',
            onSalvar: () async {
              salvou++;
              return erro;
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('Salvar no celular'));
      await tester.pump();
      expect(salvou, 1);
      expect(find.text('Foto salva na galeria do celular (álbum $kAlbum).'), findsOneWidget);

      erro = 'Sem permissão para salvar na galeria do celular.';
      await tester.tap(find.byTooltip('Salvar no celular'));
      await tester.pump();
      expect(find.text(erro), findsOneWidget);
    });

    testWidgets('sem nada guardado não há Excluir; sem imagem o Salvar fica desligado', (tester) async {
      _celular(tester);
      await tester.pumpWidget(_app(const VisualizadorDeImagem(imagem: null, titulo: 'Tela')));
      expect(find.byTooltip('Excluir'), findsNothing);
      final salvar = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.download_outlined), matching: find.byType(IconButton)),
      );
      expect(salvar.onPressed, isNull);
      expect(find.text('Tela indisponível agora'), findsOneWidget);
    });

    testWidgets('Excluir confirma; Cancelar não apaga; confirmado apaga, avisa e fecha', (tester) async {
      _celular(tester);
      var apagou = 0;
      bool? excluida;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    excluida = await abrirImagem(
                      ctx,
                      bytes: _png,
                      titulo: 'Quem está no computador — Ana',
                      nomeArquivo: 'Foto Ana',
                      onSalvar: () async => null,
                      onExcluir: () async {
                        apagou++;
                        return null;
                      },
                      avisoAoExcluir: 'A captura sai da nuvem.',
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir esta foto?'), findsOneWidget);
      expect(find.text('A captura sai da nuvem.'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(apagou, 0);

      await tester.tap(find.byTooltip('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();
      expect(apagou, 1);
      expect(excluida, isTrue);
      expect(find.text('Foto excluída.'), findsOneWidget);
      expect(find.text('Quem está no computador — Ana'), findsNothing);
    });

    testWidgets('Excluir que falha avisa e a foto continua aberta', (tester) async {
      _celular(tester);
      await tester.pumpWidget(
        _app(
          VisualizadorDeImagem(
            imagem: MemoryImage(_png),
            titulo: 'Foto',
            onSalvar: () async => null,
            onExcluir: () async => 'Não deu para excluir a foto.',
          ),
        ),
      );
      await tester.tap(find.byTooltip('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Não deu para excluir a foto.'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
    });

    testWidgets('ação a mais fecha a tela cheia e roda', (tester) async {
      _celular(tester);
      var historico = 0;
      bool? excluida;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    excluida = await abrirImagem(
                      ctx,
                      bytes: _png,
                      titulo: 'Unidade 7',
                      nomeArquivo: 'Unidade 7',
                      onSalvar: () async => null,
                      extras: [
                        AcaoDaMidia(icone: Icons.history, dica: 'Ver histórico', onPressed: () => historico++),
                      ],
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver histórico'));
      await tester.pumpAndSettle();
      expect(historico, 1);
      expect(excluida, isFalse);
      expect(find.text('Unidade 7'), findsNothing);
    });
  });

  group('vídeo', () {
    late _VideoFalso plataforma;
    late List<MethodCall> sistema;

    setUp(() {
      plataforma = _VideoFalso();
      VideoPlayerPlatform.instance = plataforma;
    });

    void ouvirSistema(WidgetTester tester) {
      sistema = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        sistema.add(c);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    Object? ultimo(String metodo) => sistema.lastWhere((c) => c.method == metodo).arguments;

    Widget video({Future<String?> Function()? onExcluir}) => _app(
          VisualizadorDeVideo(
            controlador: VideoPlayerController.file(File('/nao/existe.mp4')),
            titulo: 'Unidade 3',
            legenda: 'Conta aluno1',
            onSalvar: () async => null,
            onExcluir: onExcluir ?? () async => null,
          ),
        );

    testWidgets('em pé: toca com a barra, Salvar e Excluir; tempo e tela cheia', (tester) async {
      _celular(tester);
      ouvirSistema(tester);
      await tester.pumpWidget(video());
      await tester.pump();
      await tester.pump();
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(plataforma.chamadas, contains('play'));
      expect(find.byTooltip('Salvar no celular'), findsOneWidget);
      expect(find.byTooltip('Excluir'), findsOneWidget);
      expect(find.byTooltip('Tela cheia'), findsOneWidget);
      expect(find.text('0:00 / 0:42'), findsOneWidget);
      expect(ultimo('SystemChrome.setEnabledSystemUIMode'), 'SystemUiMode.edgeToEdge');
    });

    testWidgets('deitar o celular vira tela cheia: some a barra do sistema e a de cima, tocando',
        (tester) async {
      _celular(tester);
      ouvirSistema(tester);
      await tester.pumpWidget(video());
      await tester.pump();
      await tester.pump();

      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pump();
      expect(ultimo('SystemChrome.setEnabledSystemUIMode'), 'SystemUiMode.immersiveSticky');
      expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(_barra(tester, 'Unidade 3'), 0);

      // Um toque traz a barra de volta.
      await tester.tapAt(tester.getCenter(find.byType(VideoPlayer)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_barra(tester, 'Unidade 3'), 1);

      // Fechar devolve a rotação livre e a barra do sistema.
      await tester.pumpWidget(const SizedBox());
      expect(ultimo('SystemChrome.setPreferredOrientations'), isEmpty);
      expect(ultimo('SystemChrome.setEnabledSystemUIMode'), 'SystemUiMode.edgeToEdge');
    });

    testWidgets('o botão de tela cheia deita e o de sair volta em pé', (tester) async {
      _celular(tester);
      ouvirSistema(tester);
      await tester.pumpWidget(video());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pump();
      expect(
        ultimo('SystemChrome.setPreferredOrientations'),
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      );
      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pump();
      await tester.tap(find.byTooltip('Sair da tela cheia'));
      await tester.pump();
      expect(ultimo('SystemChrome.setPreferredOrientations'), ['DeviceOrientation.portraitUp']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pausar e tocar de novo', (tester) async {
      _celular(tester);
      ouvirSistema(tester);
      await tester.pumpWidget(video());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pump();
      expect(plataforma.chamadas.last, 'pause');
      await tester.tap(find.byTooltip('Tocar'));
      await tester.pump();
      expect(plataforma.chamadas.last, 'play');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
