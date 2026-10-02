// Grade de telas ao vivo (item 23): uma miniatura por PC da turma. Enquanto a
// grade está na frente, o app renova state/monitor a cada 10 s e assina
// /thumbs/{id}; ao sair (outra aba, outra tela por cima, app em segundo
// plano, aula encerrada) apaga state/monitor e as miniaturas — o PC para de
// capturar. Nada vai para o disco (só memória). Ver SPEC-turma §5.4.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../cloud/thumb_estado.dart';
import '../pairing/pairing_controller.dart';
import '../util/natural_sort.dart';
import '../util/versao.dart';
import 'theme.dart';

/// Observa as trocas de TELA (rotas de página; diálogos e sheets não contam):
/// a grade para quando outra tela cobre a aba Aula. Registrado no MaterialApp.
final RouteObserver<PageRoute<dynamic>> observadorDeRotas =
    RouteObserver<PageRoute<dynamic>>();

/// Imagem que veio de um PC: decodificada no máximo em [largura]×[altura]
/// (mantendo a proporção, nunca aumentando). Um JPEG que declara dimensões
/// enormes não estoura a memória do celular.
ImageProvider imagemDoPc(
  Uint8List bytes, {
  int largura = 960,
  int altura = 600,
}) =>
    ResizeImage(
      MemoryImage(bytes),
      width: largura,
      height: altura,
      policy: ResizeImagePolicy.fit,
    );

class GradeTelas extends StatefulWidget {
  const GradeTelas({
    super.key,
    required this.pairing,
    this.visivel = true,
    this.onAbrirPc,
  });

  final PairingController pairing;

  /// A aba Aula está na frente (o IndexedStack mantém as abas montadas).
  final bool visivel;

  /// Quadro sem imagem: abre a tela do PC.
  final void Function(String deviceId)? onAbrirPc;

  @override
  State<GradeTelas> createState() => _GradeTelasState();
}

class _GradeTelasState extends State<GradeTelas>
    with WidgetsBindingObserver, RouteAware {
  PairingController get _p => widget.pairing;

  bool _appNaFrente = true;
  bool _coberta = false;
  bool _rodando = false;
  PageRoute<dynamic>? _rota;

  // "há 12 s" anda sozinho entre uma miniatura e outra.
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final estado = WidgetsBinding.instance.lifecycleState;
    _appNaFrente = estado == null || estado == AppLifecycleState.resumed;
    _p.addListener(_onChange);
    _relogio = Timer.periodic(const Duration(seconds: 5), (_) => _onChange());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rota = ModalRoute.of(context);
    if (rota is PageRoute<dynamic> && !identical(rota, _rota)) {
      observadorDeRotas.unsubscribe(this);
      observadorDeRotas.subscribe(this, rota);
      _rota = rota;
    }
  }

  @override
  void didUpdateWidget(GradeTelas old) {
    super.didUpdateWidget(old);
    if (old.visivel != widget.visivel) _sincronizar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    observadorDeRotas.unsubscribe(this);
    _relogio?.cancel();
    _p.removeListener(_onChange);
    if (_rodando) unawaited(_p.fecharGrade());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appNaFrente = true;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appNaFrente = false;
      case AppLifecycleState.inactive:
        return; // passageiro (cortina de notificações, troca de app)
    }
    _sincronizar();
  }

  @override
  void didPushNext() {
    _coberta = true;
    _sincronizar();
  }

  @override
  void didPopNext() {
    _coberta = false;
    _sincronizar();
  }

  void _onChange() {
    if (!mounted) return;
    // A grade está na frente, mas o pedido de abrir foi recusado (a turma
    // estava vazia naquele instante): abre quando a turma aparecer, senão os
    // quadros ficariam em "Carregando…" para sempre.
    if (_rodando && !_p.gradeAberta && _p.motivoSemTurma == null) {
      unawaited(_p.abrirGrade());
    }
    setState(() {});
  }

  // Liga a grade só quando ela está mesmo na frente; desliga (apagando
  // state/monitor e as miniaturas) assim que deixa de estar.
  void _sincronizar() {
    final deve = mounted && widget.visivel && _appNaFrente && !_coberta;
    if (deve && !_rodando) {
      _rodando = true;
      unawaited(_p.abrirGrade());
    } else if (!deve && _rodando) {
      _rodando = false;
      unawaited(_p.fecharGrade());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = [..._p.pcsDaTurma]
      ..sort((a, b) => compararNatural(_p.nomeDoPc(a), _p.nomeDoPc(b)));
    final erro = _p.erroGrade;
    if (ids.isEmpty) {
      return _mensagem(
        _p.motivoSemTurma ?? 'Nenhum computador com aluno nesta aula ainda.',
      );
    }
    final agora = _p.agoraServidorMs();
    final abertaEm = _p.gradeAbertaEm;
    final provaLigada = _p.provaLigada;
    return Column(
      children: [
        if (erro != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 18,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      erro,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              const espaco = 12.0;
              final colunas = colunasDaGrade(box.maxWidth);
              final largura = (box.maxWidth - espaco * (colunas + 1)) / colunas;
              // Quadro em 16:10 + rodapé com nome e idade (uma linha a mais
              // quando algum PC antigo está "sem modo prova"); o rodapé
              // cresce com o tamanho de letra do celular.
              final linhaExtra = provaLigada &&
                  ids.any((id) => !suportaTurma(_p.pcPorId(id)?.versaoExt));
              final rodape = 14 +
                  MediaQuery.textScalerOf(context).scale(linhaExtra ? 38 : 30);
              final altura = largura * 10 / 16 + rodape;
              return GridView.builder(
                padding: const EdgeInsets.all(espaco),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colunas,
                  mainAxisSpacing: espaco,
                  crossAxisSpacing: espaco,
                  childAspectRatio: largura / altura,
                ),
                itemCount: ids.length,
                itemBuilder: (context, i) {
                  final id = ids[i];
                  final s = _p.pcPorId(id);
                  final online = s != null && _p.isOnline(s);
                  final suporta = suportaTurma(s?.versaoExt);
                  final thumb = _p.miniaturaDe(id);
                  final estado = estadoDoQuadro(
                    online: online,
                    suportaTurma: suporta,
                    thumb: thumb,
                    gradeAbertaEm: abertaEm,
                    agoraMs: agora,
                  );
                  return QuadroDaTela(
                    nome: _p.nomeDoPc(id),
                    online: online,
                    estado: estado,
                    jpeg: estado.temImagem ? thumb?.jpeg : null,
                    versaoImagem: thumb?.ts ?? 0,
                    travada: _p.telaTravada(id),
                    maoLevantada: _p.maoLevantada(id),
                    semModoProva: provaLigada && !suporta,
                    onTap: () => estado.temImagem
                        ? _ampliar(id)
                        : widget.onAbrirPc?.call(id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _mensagem(String texto) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // Toque para ampliar: no Celita OS pede a tela inteira (capture_screen) e
  // mostra a miniatura enquanto ela não chega; no Chromebook só amplia.
  Future<void> _ampliar(String deviceId) {
    final s = _p.pcPorId(deviceId);
    final celita = s != null && temCelita(s.versaoExt) && _p.isOnline(s);
    return showDialog<void>(
      context: context,
      builder: (ctx) => _TelaAmpliada(
        pairing: _p,
        deviceId: deviceId,
        nome: _p.nomeDoPc(deviceId),
        telaInteira: celita ? _p.tirarFotoTela(deviceId) : null,
      ),
    );
  }
}

/// Um quadro da grade: a miniatura (ou o texto no lugar dela) em 16:10 e o
/// rodapé com o ponto de online, o nome e a idade.
class QuadroDaTela extends StatelessWidget {
  const QuadroDaTela({
    super.key,
    required this.nome,
    required this.online,
    required this.estado,
    this.jpeg,
    this.versaoImagem = 0,
    this.travada = false,
    this.maoLevantada = false,
    this.semModoProva = false,
    this.onTap,
  });

  final String nome;
  final bool online;
  final EstadoQuadro estado;
  final Uint8List? jpeg;

  /// `ts` da miniatura: imagem nova troca com fade de 150 ms.
  final int versaoImagem;
  final bool travada;
  final bool maoLevantada;
  final bool semModoProva;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = cores(context);
    final texto = Theme.of(context).textTheme;
    final img = jpeg;
    Widget area;
    if (estado.temImagem && img != null) {
      area = AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Opacity(
          key: ValueKey(versaoImagem),
          opacity: estado.esmaecida ? 0.5 : 1,
          child: Image(
            image: imagemDoPc(img),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) =>
                _textoNoQuadro(context, 'Tela indisponível agora'),
          ),
        ),
      );
    } else if (estado.tipo == TipoQuadro.carregando) {
      area = Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          estado.texto,
          style: texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else {
      area = _textoNoQuadro(context, estado.texto, icone: _icone(estado.tipo));
    }

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.surfaceContainer, child: area),
                  if (travada || maoLevantada)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Row(
                        children: [
                          if (travada)
                            _Selo(
                              icone: Icons.lock,
                              fundo: scheme.primary,
                              frente: scheme.onPrimary,
                              dica: 'Tela travada',
                            ),
                          if (maoLevantada)
                            _Selo(
                              icone: Icons.back_hand,
                              fundo: c.atencao,
                              frente: scheme.surface,
                              dica: 'Mão levantada',
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: online ? c.online : c.offline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texto.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (semModoProva)
                            Text(
                              'sem modo prova — versão antiga',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  texto.labelSmall?.copyWith(color: c.atencao),
                            ),
                        ],
                      ),
                    ),
                    if (estado.temImagem)
                      Text(
                        estado.texto,
                        style: texto.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icone(TipoQuadro t) => switch (t) {
        TipoQuadro.desligado => Icons.power_settings_new,
        TipoQuadro.versaoAntiga => Icons.system_update_alt,
        TipoQuadro.ninguemLogado => Icons.person_off_outlined,
        TipoQuadro.naoPermitida => Icons.visibility_off_outlined,
        _ => Icons.desktop_access_disabled_outlined,
      };

  Widget _textoNoQuadro(BuildContext context, String texto, {IconData? icone}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icone != null)
            Icon(icone, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            texto,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({
    required this.icone,
    required this.fundo,
    required this.frente,
    required this.dica,
  });

  final IconData icone;
  final Color fundo;
  final Color frente;
  final String dica;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: dica,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: fundo, shape: BoxShape.circle),
          child: Icon(icone, size: 14, color: frente),
        ),
      ),
    );
  }
}

/// Miniatura ampliada; no Celita OS troca pela tela inteira quando ela chega.
class _TelaAmpliada extends StatelessWidget {
  const _TelaAmpliada({
    required this.pairing,
    required this.deviceId,
    required this.nome,
    this.telaInteira,
  });

  final PairingController pairing;
  final String deviceId;
  final String nome;
  final Future<Uint8List?>? telaInteira;

  @override
  Widget build(BuildContext context) {
    final legendaEstilo = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: telaInteira,
        builder: (context, snap) {
          final cheia = snap.data;
          final esperando = telaInteira != null &&
              snap.connectionState != ConnectionState.done;
          return ListenableBuilder(
            listenable: pairing,
            builder: (context, _) {
              final thumb = pairing.miniaturaDe(deviceId);
              final mini = thumb?.jpeg;
              // A miniatura usa o mesmo tamanho do quadro (já decodificada:
              // aparece na hora); a tela inteira, um limite maior.
              final ImageProvider? imagem = cheia != null
                  ? imagemDoPc(cheia, largura: 2560, altura: 1600)
                  : mini != null
                      ? imagemDoPc(mini)
                      : null;
              // Idade da miniatura ("há 2 min"), ao lado do nome, como no
              // rodapé do quadro.
              var idade = '';
              if (cheia == null && thumb != null && mini != null) {
                final e = estadoDoQuadro(
                  online: true,
                  suportaTurma: true,
                  thumb: thumb,
                  gradeAbertaEm: null,
                  agoraMs: pairing.agoraServidorMs(),
                );
                idade = e.texto;
              }
              final String legenda;
              if (cheia != null) {
                legenda = 'Tela inteira agora.';
              } else if (esperando) {
                legenda = 'Buscando a tela em tamanho maior…';
              } else if (telaInteira != null) {
                legenda = 'A tela maior não veio agora — esta é a miniatura.';
              } else {
                legenda = 'Miniatura da aba aberta neste computador.';
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (idade.isNotEmpty) Text(idade, style: legendaEstilo),
                        IconButton(
                          tooltip: 'Fechar',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  if (esperando) const LinearProgressIndicator(minHeight: 2),
                  if (imagem != null)
                    InteractiveViewer(
                      maxScale: 4,
                      child: Image(
                        image: imagem,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Tela indisponível agora',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(legenda, style: legendaEstilo),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
