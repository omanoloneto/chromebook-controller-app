// Fotos e vídeos tirados na Câmera de um PC do Celita OS: as da pasta de cada
// conta e as que o logout dos alunos guardou no PC (15 dias). Baixar salva na
// galeria do celular; apagar tira do PC.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../cloud/archive_store.dart';
import '../cloud/media_store.dart';
import '../pairing/pairing_controller.dart';
import '../util/versao.dart';
import 'archive_page.dart';
import 'device_page.dart';
import 'theme.dart';

const String kAlbum = 'Controle de Aula';

String _dois(int n) => n.toString().padLeft(2, '0');

/// "850 KB", "12,3 MB", "1,2 GB".
String tamanhoLegivel(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  final mb = bytes / (1024 * 1024);
  if (mb < 1024) return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(mb / 1024).toStringAsFixed(1).replaceAll('.', ',')} GB';
}

/// "0:42", "12:05", "1:02:03".
String duracaoLegivel(double segundos) {
  final total = segundos.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${_dois(m)}:${_dois(s)}' : '$m:${_dois(s)}';
}

String mensagemDeMidia(Object erro) {
  if (erro is! MidiaException) return 'Não deu para baixar. Tente de novo.';
  return switch (erro.motivo) {
    'pc_falhou' => 'O PC não conseguiu enviar este arquivo. Tente de novo.',
    'sem_progresso' => 'O envio parou. Confira a internet do PC e do celular.',
    'parte_ilegivel' => 'O arquivo chegou corrompido. Tente de novo.',
    'download' => 'Não deu para baixar. Confira a internet do celular.',
    _ => erro.motivo,
  };
}

class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.pairing, required this.deviceId});

  final PairingController pairing;
  final String deviceId;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  late final MediaStore? _store = widget.pairing.midiaDe(widget.deviceId);
  late final Stream<List<MediaItem>>? _itens = _store?.watch();
  final Set<String> _selecionados = {};
  final Map<String, double> _progresso = {};
  bool _baixando = false;

  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _snack(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  String get _nome {
    final s = widget.pairing.pcPorId(widget.deviceId);
    return s != null ? widget.pairing.nomeDe(s) : 'PC';
  }

  Future<void> _baixar(List<MediaItem> itens) async {
    final store = _store;
    if (store == null || itens.isEmpty || _baixando) return;
    final s = widget.pairing.pcPorId(widget.deviceId);
    if (s == null || !widget.pairing.isOnline(s)) {
      _snack('O PC está desligado. Ligue-o para baixar.');
      return;
    }
    try {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        _snack('Sem permissão para salvar na galeria do celular.');
        return;
      }
    } catch (_) {}
    setState(() {
      _baixando = true;
      _selecionados.clear();
    });
    var salvos = 0;
    String? erro;
    final pasta = Directory('${(await getTemporaryDirectory()).path}/midia');
    await pasta.create(recursive: true);
    for (final item in itens) {
      if (!mounted) break;
      setState(() => _progresso[item.mid] = 0);
      final destino = File('${pasta.path}/${item.nome.replaceAll('/', '-')}');
      try {
        await store.baixar(
          item,
          destino,
          pedir: () => widget.pairing.pedirEnvioDeMidia(widget.deviceId, item.mid),
          onProgress: (f) {
            if (mounted) setState(() => _progresso[item.mid] = f);
          },
        );
        if (item.video) {
          await Gal.putVideo(destino.path, album: kAlbum);
        } else {
          await Gal.putImage(destino.path, album: kAlbum);
        }
        salvos++;
      } on GalException {
        erro = 'Não deu para salvar na galeria do celular.';
      } catch (e) {
        erro = mensagemDeMidia(e);
      } finally {
        try {
          if (await destino.exists()) await destino.delete();
        } catch (_) {}
        if (mounted) setState(() => _progresso.remove(item.mid));
      }
      if (erro != null) break;
    }
    if (!mounted) return;
    setState(() => _baixando = false);
    if (salvos > 0) {
      final quantos = salvos == 1 ? '1 arquivo salvo' : '$salvos arquivos salvos';
      _snack(erro == null ? '$quantos na galeria (álbum $kAlbum).' : '$quantos. $erro');
    } else if (erro != null) {
      _snack(erro);
    }
  }

  Future<void> _apagar(List<MediaItem> itens) async {
    if (itens.isEmpty) return;
    final n = itens.length;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'Apagar do PC?' : 'Apagar $n arquivos do PC?'),
        content: const Text('Eles somem do computador e não dá para desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    final erro = await esperarComSpinner(
      context,
      n == 1 ? 'Apagando…' : 'Apagando $n arquivos…',
      widget.pairing.apagarMidias(widget.deviceId, [for (final i in itens) i.mid]),
    );
    if (!mounted) return;
    setState(_selecionados.clear);
    _snack(erro ?? (n == 1 ? 'Apagado do PC.' : '$n arquivos apagados do PC.'));
  }

  Future<void> _detalhes(MediaItem item) async {
    final quando = DateTime.fromMillisecondsSinceEpoch(item.ts);
    final expira = item.expira != null ? DateTime.fromMillisecondsSinceEpoch(item.expira!) : null;
    final acao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.thumb != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(item.thumb!, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ListTile(
              title: Text(item.nome),
              subtitle: Text(
                [
                  'Conta ${item.conta}',
                  '${_dois(quando.day)}/${_dois(quando.month)} às ${_dois(quando.hour)}:${_dois(quando.minute)}',
                  tamanhoLegivel(item.bytes),
                  if (item.duracao != null) duracaoLegivel(item.duracao!),
                ].join(' · '),
              ),
            ),
            if (expira != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule),
                title: Text(
                  'Saiu da pasta do aluno ao sair da conta. Fica no PC até '
                  '${_dois(expira.day)}/${_dois(expira.month)}.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'apagar'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Apagar do PC'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'baixar'),
                      icon: const Icon(Icons.download),
                      label: const Text('Baixar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (acao == 'baixar') await _baixar([item]);
    if (acao == 'apagar') await _apagar([item]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: _itens,
      builder: (context, snap) {
        final itens = snap.data ?? const <MediaItem>[];
        final escolhidos = [for (final i in itens) if (_selecionados.contains(i.mid)) i];
        return Scaffold(
          appBar: escolhidos.isEmpty
              ? AppBar(
                  title: Text('Fotos e vídeos — $_nome'),
                  actions: [
                    if (itens.isNotEmpty)
                      IconButton(
                        tooltip: 'Baixar tudo',
                        onPressed: _baixando ? null : () => _baixar(itens),
                        icon: const Icon(Icons.download),
                      ),
                  ],
                )
              : AppBar(
                  leading: IconButton(
                    tooltip: 'Cancelar seleção',
                    onPressed: () => setState(_selecionados.clear),
                    icon: const Icon(Icons.close),
                  ),
                  title: Text('${escolhidos.length} selecionado${escolhidos.length == 1 ? '' : 's'}'),
                  actions: [
                    IconButton(
                      tooltip: 'Selecionar tudo',
                      onPressed: () => setState(() => _selecionados.addAll(itens.map((i) => i.mid))),
                      icon: const Icon(Icons.select_all),
                    ),
                    IconButton(
                      tooltip: 'Baixar',
                      onPressed: _baixando ? null : () => _baixar(escolhidos),
                      icon: const Icon(Icons.download),
                    ),
                    IconButton(
                      tooltip: 'Apagar do PC',
                      onPressed: () => _apagar(escolhidos),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
          body: _corpo(snap, itens),
        );
      },
    );
  }

  Widget _mensagem(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      );

  Widget _corpo(AsyncSnapshot<List<MediaItem>> snap, List<MediaItem> itens) {
    final s = widget.pairing.pcPorId(widget.deviceId);
    if (s == null || _store == null) return _mensagem('Este PC não está mais conectado.');
    if (!temCelita(s.versaoExt)) {
      return _mensagem('As fotos e vídeos da Câmera existem só nos PCs com Celita OS.');
    }
    if (!widget.pairing.workspaceAtivo) {
      return _mensagem('As fotos e vídeos da Câmera chegam só dos PCs da escola.');
    }
    if (snap.hasError) return _mensagem('Não deu para carregar. Confira a internet do celular.');
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (itens.isEmpty) {
      return _mensagem('Nenhuma foto ou vídeo tirado na Câmera deste PC.');
    }
    final grupos = <String, List<MediaItem>>{};
    for (final item in itens) {
      (grupos[dayOf(item.ts)] ??= []).add(item);
    }
    final hoje = dayOf(widget.pairing.agoraServidorMs());
    final dias = grupos.keys.toList();
    return CustomScrollView(
      slivers: [
        if (!widget.pairing.isOnline(s))
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text('Este PC está desligado. Dá para ver a lista, mas baixar e apagar '
                  'só com ele ligado.'),
            ),
          ),
        for (final dia in dias) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                rotuloDoDia(dia, dia == hoje ? 0 : (dayStartMs(hoje) - dayStartMs(dia)) ~/ 86400000),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 16 / 11,
              ),
              delegate: SliverChildListDelegate([for (final item in grupos[dia]!) _tile(item)]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _tile(MediaItem item) {
    final tema = Theme.of(context);
    final selecionado = _selecionados.contains(item.mid);
    final progresso = _progresso[item.mid];
    final quando = DateTime.fromMillisecondsSinceEpoch(item.ts);
    return Semantics(
      label: '${item.video ? 'Vídeo' : 'Foto'} da conta ${item.conta}',
      selected: selecionado,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (_selecionados.isNotEmpty) {
            setState(() => selecionado ? _selecionados.remove(item.mid) : _selecionados.add(item.mid));
          } else {
            _detalhes(item);
          }
        },
        onLongPress: () => setState(() => _selecionados.add(item.mid)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: tema.colorScheme.surfaceContainerHighest,
                child: item.thumb != null
                    ? Image.memory(item.thumb!, fit: BoxFit.cover, gaplessPlayback: true)
                    : Icon(
                        item.video ? Icons.videocam_outlined : Icons.photo_outlined,
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (item.video) const Icon(Icons.play_circle_outline, size: 14, color: Colors.white),
                      if (item.video) const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          [
                            '${_dois(quando.hour)}:${_dois(quando.minute)}',
                            item.conta,
                            if (item.video && item.duracao != null) duracaoLegivel(item.duracao!),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (item.guardado)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Tooltip(
                    message: 'Guardado no PC depois que o aluno saiu da conta',
                    child: Icon(Icons.inventory_2_outlined, size: 16, color: cores(context).atencao),
                  ),
                ),
              if (selecionado)
                Container(
                  color: tema.colorScheme.primary.withValues(alpha: 0.35),
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.check_circle, color: Colors.white),
                ),
              if (progresso != null)
                Container(
                  color: Colors.black45,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    value: progresso > 0 ? progresso : null,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
