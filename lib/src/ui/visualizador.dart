// Tela cheia para tudo o que o app abre de foto e vídeo: zoom (pinça e toque
// duplo) nas fotos; nos vídeos, o player que vira tela cheia ao deitar o
// celular. Em todos: salvar no celular e excluir de onde estiver guardado.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import 'componentes.dart';

/// Álbum da galeria onde o app salva fotos e vídeos.
const String kAlbum = 'Controle de Aula';

/// Ação a mais na barra (ex.: "Ver histórico"): fecha a tela cheia e roda.
class AcaoDaMidia {
  const AcaoDaMidia({required this.icone, required this.dica, required this.onPressed});

  final IconData icone;
  final String dica;
  final VoidCallback onPressed;
}

Future<bool> _acessoAGaleria() async {
  try {
    return await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
  } catch (_) {
    // Alguns aparelhos não respondem à consulta; o salvar diz se deu.
    return true;
  }
}

/// Salva uma imagem na galeria do celular. null = salvou; senão o motivo.
Future<String?> salvarImagemNaGaleria(Uint8List bytes, String nome) async {
  if (!await _acessoAGaleria()) return 'Sem permissão para salvar na galeria do celular.';
  try {
    await Gal.putImageBytes(bytes, album: kAlbum, name: nome);
    return null;
  } catch (_) {
    return 'Não deu para salvar na galeria do celular.';
  }
}

/// Salva um arquivo de foto ou vídeo na galeria. null = salvou.
Future<String?> salvarArquivoNaGaleria(String caminho, {required bool video}) async {
  if (!await _acessoAGaleria()) return 'Sem permissão para salvar na galeria do celular.';
  try {
    if (video) {
      await Gal.putVideo(caminho, album: kAlbum);
    } else {
      await Gal.putImage(caminho, album: kAlbum);
    }
    return null;
  } catch (_) {
    return 'Não deu para salvar na galeria do celular.';
  }
}

/// Abre [bytes] em tela cheia. Devolve true se a foto foi excluída.
Future<bool> abrirImagem(
  BuildContext context, {
  required Uint8List bytes,
  required String titulo,
  String? legenda,
  required String nomeArquivo,
  Future<String?> Function()? onSalvar,
  Future<String?> Function()? onExcluir,
  String avisoAoExcluir = 'A foto some da nuvem e do computador. Não dá para desfazer.',
  List<AcaoDaMidia> extras = const [],
}) async {
  final excluiu = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => VisualizadorDeImagem(
        imagem: MemoryImage(bytes),
        titulo: titulo,
        legenda: legenda,
        onSalvar: onSalvar ?? () => salvarImagemNaGaleria(bytes, nomeArquivo),
        onExcluir: onExcluir,
        avisoAoExcluir: avisoAoExcluir,
        extras: extras,
      ),
    ),
  );
  return excluiu == true;
}

/// Abre o vídeo de [arquivo] em tela cheia. Devolve true se foi excluído.
Future<bool> abrirVideo(
  BuildContext context, {
  required File arquivo,
  required String titulo,
  String? legenda,
  Future<String?> Function()? onExcluir,
  String avisoAoExcluir = 'O vídeo some da nuvem e do computador. Não dá para desfazer.',
}) async {
  final excluiu = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => VisualizadorDeVideo(
        controlador: VideoPlayerController.file(arquivo),
        titulo: titulo,
        legenda: legenda,
        onSalvar: () => salvarArquivoNaGaleria(arquivo.path, video: true),
        onExcluir: onExcluir,
        avisoAoExcluir: avisoAoExcluir,
      ),
    ),
  );
  return excluiu == true;
}

/// Salvar e excluir, iguais na foto e no vídeo.
mixin _AcoesDaMidia<T extends StatefulWidget> on State<T> {
  bool _ocupado = false;

  void _snack(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _salvar(Future<String?> Function() salvar, String feito) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final erro = await salvar();
    if (!mounted) return;
    setState(() => _ocupado = false);
    _snack(erro ?? feito);
  }

  Future<void> _excluir(
    Future<String?> Function() excluir, {
    required String titulo,
    required String aviso,
    required String feito,
  }) async {
    if (_ocupado) return;
    final ok = await confirmar(context, titulo: titulo, mensagem: aviso, acao: 'Excluir', destrutiva: true);
    if (!ok || !mounted) return;
    setState(() => _ocupado = true);
    final erro = await esperarComSpinner(context, 'Excluindo…', excluir());
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (erro != null) {
      _snack(erro);
      return;
    }
    _snack(feito);
    Navigator.of(context).pop(true);
  }

  List<Widget> _botoes({
    required List<AcaoDaMidia> extras,
    required Future<String?> Function()? onSalvar,
    required VoidCallback? salvar,
    required VoidCallback? excluir,
  }) =>
      [
        for (final a in extras)
          IconButton(
            tooltip: a.dica,
            icon: Icon(a.icone),
            onPressed: () {
              Navigator.of(context).pop(false);
              a.onPressed();
            },
          ),
        IconButton(
          tooltip: 'Salvar no celular',
          icon: const Icon(Icons.download_outlined),
          onPressed: onSalvar == null || _ocupado ? null : salvar,
        ),
        if (excluir != null)
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: _ocupado ? null : excluir,
          ),
      ];
}

/// Fundo preto, a mídia por baixo e a barra (voltar, título, legenda e ações)
/// por cima; a barra some e volta com [barraVisivel].
class MolduraDeMidia extends StatelessWidget {
  const MolduraDeMidia({
    super.key,
    required this.titulo,
    this.legenda,
    required this.acoes,
    required this.barraVisivel,
    required this.child,
    this.carregando = false,
    this.rodape,
  });

  final String titulo;
  final String? legenda;
  final List<Widget> acoes;
  final bool barraVisivel;
  final Widget child;
  final bool carregando;
  final Widget? rodape;

  Widget _some(Widget filho) => AnimatedOpacity(
        opacity: barraVisivel ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(ignoring: !barraVisivel, child: filho),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Align(
                alignment: Alignment.topCenter,
                child: _some(
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC000000), Color(0x00000000)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                            child: Row(
                              children: [
                                const BackButton(color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        titulo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.titleMedium?.copyWith(color: Colors.white),
                                      ),
                                      if (legenda != null && legenda!.isNotEmpty)
                                        Text(
                                          legenda!,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.bodySmall?.copyWith(color: Colors.white70),
                                        ),
                                    ],
                                  ),
                                ),
                                ...acoes,
                              ],
                            ),
                          ),
                          if (carregando)
                            const LinearProgressIndicator(minHeight: 2, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (rodape != null) Align(alignment: Alignment.bottomCenter, child: _some(rodape!)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foto em tela cheia: pinça ou toque duplo para o zoom, um toque esconde a
/// barra. [imagem] null = ainda não há o que mostrar (texto no lugar).
class VisualizadorDeImagem extends StatefulWidget {
  const VisualizadorDeImagem({
    super.key,
    required this.imagem,
    required this.titulo,
    this.legenda,
    this.carregando = false,
    this.onSalvar,
    this.onExcluir,
    this.avisoAoExcluir = 'A foto some da nuvem e do computador. Não dá para desfazer.',
    this.extras = const [],
  });

  final ImageProvider? imagem;
  final String titulo;
  final String? legenda;
  final bool carregando;

  /// null = nada para salvar ainda (o botão fica desligado).
  final Future<String?> Function()? onSalvar;

  /// null = sem Excluir (nada guardado para apagar).
  final Future<String?> Function()? onExcluir;
  final String avisoAoExcluir;
  final List<AcaoDaMidia> extras;

  @override
  State<VisualizadorDeImagem> createState() => _VisualizadorDeImagemState();
}

class _VisualizadorDeImagemState extends State<VisualizadorDeImagem>
    with _AcoesDaMidia<VisualizadorDeImagem> {
  static const double _zoomDoToqueDuplo = 2.5;

  final _zoom = TransformationController();
  Offset _pontoDoToque = Offset.zero;
  bool _barra = true;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _alternarZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const k = _zoomDoToqueDuplo;
    _zoom.value = Matrix4.diagonal3Values(k, k, 1)
      ..setTranslationRaw(-_pontoDoToque.dx * (k - 1), -_pontoDoToque.dy * (k - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final onSalvar = widget.onSalvar;
    final onExcluir = widget.onExcluir;
    final imagem = widget.imagem;
    return MolduraDeMidia(
      titulo: widget.titulo,
      legenda: widget.legenda,
      carregando: widget.carregando,
      barraVisivel: _barra,
      acoes: _botoes(
        extras: widget.extras,
        onSalvar: onSalvar,
        salvar: onSalvar == null
            ? null
            : () => _salvar(onSalvar, 'Foto salva na galeria do celular (álbum $kAlbum).'),
        excluir: onExcluir == null
            ? null
            : () => _excluir(
                  onExcluir,
                  titulo: 'Excluir esta foto?',
                  aviso: widget.avisoAoExcluir,
                  feito: 'Foto excluída.',
                ),
      ),
      child: GestureDetector(
        onTap: () => setState(() => _barra = !_barra),
        onDoubleTapDown: (d) => _pontoDoToque = d.localPosition,
        onDoubleTap: _alternarZoom,
        child: InteractiveViewer(
          transformationController: _zoom,
          maxScale: 6,
          child: SizedBox.expand(
            child: imagem == null
                ? const Center(
                    child: Text('Tela indisponível agora', style: TextStyle(color: Colors.white70)),
                  )
                : Image(
                    image: imagem,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('Não deu para abrir esta imagem.', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Vídeo em tela cheia. Deitar o celular (ou o botão de tela cheia) esconde a
/// barra do sistema; a barra e os controles somem sozinhos enquanto toca.
class VisualizadorDeVideo extends StatefulWidget {
  const VisualizadorDeVideo({
    super.key,
    required this.controlador,
    required this.titulo,
    this.legenda,
    this.onSalvar,
    this.onExcluir,
    this.avisoAoExcluir = 'O vídeo some da nuvem e do computador. Não dá para desfazer.',
  });

  /// A tela inicializa e descarta.
  final VideoPlayerController controlador;
  final String titulo;
  final String? legenda;
  final Future<String?> Function()? onSalvar;
  final Future<String?> Function()? onExcluir;
  final String avisoAoExcluir;

  @override
  State<VisualizadorDeVideo> createState() => _VisualizadorDeVideoState();
}

class _VisualizadorDeVideoState extends State<VisualizadorDeVideo>
    with _AcoesDaMidia<VisualizadorDeVideo> {
  VideoPlayerController get _video => widget.controlador;
  bool _barra = true;
  bool _erro = false;
  bool? _deitado;
  Timer? _esconder;

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _video.play();
      _agendarEsconder();
    }).catchError((Object _) {
      if (mounted) setState(() => _erro = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deitado = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (deitado == _deitado) return;
    _deitado = deitado;
    // Deitado é tela cheia de verdade: sem a barra do Android.
    SystemChrome.setEnabledSystemUIMode(deitado ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (deitado) _agendarEsconder();
  }

  @override
  void dispose() {
    _esconder?.cancel();
    _video.dispose();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _agendarEsconder() {
    _esconder?.cancel();
    _esconder = Timer(const Duration(seconds: 3), () {
      if (mounted && _video.value.isPlaying) setState(() => _barra = false);
    });
  }

  void _alternarBarra() {
    setState(() => _barra = !_barra);
    if (_barra) _agendarEsconder();
  }

  void _tocarOuPausar() {
    final v = _video.value;
    if (v.isPlaying) {
      _video.pause();
      _esconder?.cancel();
    } else {
      if (v.duration > Duration.zero && v.position >= v.duration) _video.seekTo(Duration.zero);
      _video.play();
      _agendarEsconder();
    }
  }

  // Para quem trava a rotação do celular: força deitado e volta.
  void _alternarTelaCheia() {
    final deitado = MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      deitado
          ? const [DeviceOrientation.portraitUp]
          : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  static String _tempo(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final onSalvar = widget.onSalvar;
    final onExcluir = widget.onExcluir;
    final deitado = MediaQuery.orientationOf(context) == Orientation.landscape;
    return MolduraDeMidia(
      titulo: widget.titulo,
      legenda: widget.legenda,
      barraVisivel: _barra,
      acoes: _botoes(
        extras: const [],
        onSalvar: onSalvar,
        salvar: onSalvar == null
            ? null
            : () => _salvar(onSalvar, 'Vídeo salvo na galeria do celular (álbum $kAlbum).'),
        excluir: onExcluir == null
            ? null
            : () => _excluir(
                  onExcluir,
                  titulo: 'Excluir este vídeo?',
                  aviso: widget.avisoAoExcluir,
                  feito: 'Vídeo excluído.',
                ),
      ),
      rodape: _erro ? null : _controles(deitado),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _alternarBarra,
        child: Center(
          child: _erro
              ? const Text('Não deu para tocar este vídeo.', style: TextStyle(color: Colors.white70))
              : ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _video,
                  builder: (_, v, __) => v.isInitialized
                      ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_video))
                      : const CircularProgressIndicator(color: Colors.white),
                ),
        ),
      ),
    );
  }

  Widget _controles(bool deitado) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _video,
            builder: (context, v, _) {
              final acabou = v.duration > Duration.zero && v.position >= v.duration;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v.isInitialized)
                    VideoProgressIndicator(
                      _video,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      colors: VideoProgressColors(
                        playedColor: Theme.of(context).colorScheme.primary,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: v.isPlaying ? 'Pausar' : (acabou ? 'Ver de novo' : 'Tocar'),
                        icon: Icon(
                          v.isPlaying ? Icons.pause : (acabou ? Icons.replay : Icons.play_arrow),
                        ),
                        onPressed: v.isInitialized ? _tocarOuPausar : null,
                      ),
                      Text(
                        '${_tempo(v.position)} / ${_tempo(v.duration)}',
                        style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: deitado ? 'Sair da tela cheia' : 'Tela cheia',
                        icon: Icon(deitado ? Icons.fullscreen_exit : Icons.fullscreen),
                        onPressed: _alternarTelaCheia,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Nome de arquivo seguro para a galeria: "Unidade 12 2026-10-17 07.42".
String nomeParaGaleria(String base, int tsMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs);
  String dois(int n) => n.toString().padLeft(2, '0');
  final limpo = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return '$limpo ${d.year}-${dois(d.month)}-${dois(d.day)} ${dois(d.hour)}.${dois(d.minute)}';
}
