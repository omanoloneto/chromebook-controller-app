// Fotos de início de sessão: a foto que o PC do Celita OS tira quando alguém
// entra numa conta, de todos os PCs da escola ou de um só, por dia. Tocar
// abre a foto para salvar na galeria do celular ou ir ao histórico daquela
// entrada.

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../cloud/archive_store.dart';
import '../pairing/pairing_controller.dart';
import '../secure/crypto.dart';
import '../util/versao.dart';
import 'archive_page.dart';
import 'device_page.dart';
import 'media_page.dart' show kAlbum;

String _dois(int n) => n.toString().padLeft(2, '0');

String _hora(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_dois(d.hour)}:${_dois(d.minute)}';
}

/// Nome do arquivo na galeria: "Unidade 12 2026-10-17 07.42".
String nomeDaFotoDeEntrada(String pc, int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final limpo = pc.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return '$limpo ${d.year}-${_dois(d.month)}-${_dois(d.day)} ${_dois(d.hour)}.${_dois(d.minute)}';
}

/// Uma foto de entrada e o PC dela.
class FotoDeEntrada {
  const FotoDeEntrada(this.deviceId, this.store, this.ref);

  final String deviceId;
  final ArchiveStore store;
  final PhotoRef ref;
}

class _Carga {
  const _Carga(this.fotos, this.falhas);

  final List<FotoDeEntrada> fotos;

  /// PCs cujo índice não carregou.
  final int falhas;
}

class FotosDeEntradaPage extends StatefulWidget {
  const FotosDeEntradaPage({super.key, required this.pairing, this.deviceId});

  final PairingController pairing;

  /// null = todos os PCs com Celita OS.
  final String? deviceId;

  @override
  State<FotosDeEntradaPage> createState() => _FotosDeEntradaPageState();
}

class _FotosDeEntradaPageState extends State<FotosDeEntradaPage> {
  late final List<String> _dias = recentDays(widget.pairing.agoraServidorMs());
  late String _dia = _dias.first;
  Future<_Carga>? _carga;
  // Uma vez por foto: rolar a grade de volta não baixa de novo.
  final Map<String, Future<ArchivedPhoto>> _fotos = {};

  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
    if (widget.pairing.workspaceAtivo) _carga = _carregar();
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

  List<String> get _pcs => widget.deviceId != null
      ? [widget.deviceId!]
      : [
          for (final s in widget.pairing.pcs)
            if (temCelita(s.versaoExt)) s.deviceId,
        ];

  String _nomeDoPc(String deviceId) {
    final s = widget.pairing.pcPorId(deviceId);
    return s != null ? widget.pairing.nomeDe(s) : 'PC';
  }

  Future<_Carga> _carregar() async {
    final dia = _dia;
    var falhas = 0;
    Future<List<FotoDeEntrada>> doPc(String id) async {
      final store = widget.pairing.arquivoDe(id);
      if (store == null) return const [];
      try {
        return [for (final ref in await store.loginPhotos(dia)) FotoDeEntrada(id, store, ref)];
      } catch (_) {
        falhas++;
        return const [];
      }
    }

    final listas = await Future.wait([for (final id in _pcs) doPc(id)]);
    final fotos = [for (final l in listas) ...l]..sort((a, b) => b.ref.ts.compareTo(a.ref.ts));
    return _Carga(fotos, falhas);
  }

  void _escolherDia(String dia) {
    if (dia == _dia) return;
    setState(() {
      _dia = dia;
      _carga = _carregar();
    });
  }

  Future<ArchivedPhoto> _foto(FotoDeEntrada f, {bool deNovo = false}) {
    final chave = '${f.deviceId}|${f.ref.path}';
    if (deNovo) _fotos.remove(chave);
    return _fotos[chave] ??= f.store.download(f.ref);
  }

  Future<void> _abrir(FotoDeEntrada f) async {
    ArchivedPhoto foto;
    try {
      // Miniatura que falhou (sem internet na hora) é baixada de novo no toque.
      foto = await esperarComSpinner(
        context,
        'Abrindo a foto…',
        _foto(f).catchError((Object _) => _foto(f, deNovo: true)),
      );
    } catch (e) {
      _snack(mensagemDaFoto(e));
      return;
    } finally {
      if (mounted) setState(() {});
    }
    if (!mounted || !continuaNaFrente(context)) return;
    final pc = _nomeDoPc(f.deviceId);
    final login = foto.login ?? f.ref.ts;
    final quando = DateTime.fromMillisecondsSinceEpoch(login);
    final acao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(foto.jpeg, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
              ListTile(
                title: Text(pc),
                subtitle: Text(
                  [
                    'Entrou às ${_hora(login)} de ${_dois(quando.day)}/${_dois(quando.month)}',
                    if (foto.user != null && foto.user!.isNotEmpty) 'conta ${foto.user}',
                  ].join(' · '),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'salvar'),
                        icon: const Icon(Icons.download),
                        label: const Text('Salvar no celular'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'historico'),
                        icon: const Icon(Icons.history),
                        label: const Text('Ver histórico'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (acao == 'salvar') await _salvar(pc, foto);
    if (acao == 'historico' && mounted) {
      final user = foto.user;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArchivePage(
            pairing: widget.pairing,
            deviceId: f.deviceId,
            dia: dayOf(login),
            entrada: user == null || foto.login == null ? null : (login: login, user: user),
          ),
        ),
      );
    }
  }

  Future<void> _salvar(String pc, ArchivedPhoto foto) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        _snack('Sem permissão para salvar na galeria do celular.');
        return;
      }
      await Gal.putImageBytes(foto.jpeg, album: kAlbum, name: nomeDaFotoDeEntrada(pc, foto.ts));
      _snack('Foto salva na galeria do celular (álbum $kAlbum).');
    } catch (_) {
      _snack('Não deu para salvar na galeria do celular.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.deviceId == null
        ? 'Fotos de início de sessão'
        : 'Início de sessão — ${_nomeDoPc(widget.deviceId!)}';
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: _corpo(),
    );
  }

  Widget _mensagem(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      );

  Widget _corpo() {
    if (!widget.pairing.workspaceAtivo) {
      return _mensagem('As fotos de início de sessão existem só nos PCs da escola.');
    }
    final id = widget.deviceId;
    if (id != null) {
      final s = widget.pairing.pcPorId(id);
      if (s == null) return _mensagem('Este PC não está mais conectado.');
      if (!temCelita(s.versaoExt)) {
        return _mensagem('As fotos de início de sessão existem só nos PCs com Celita OS.');
      }
    }
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (var i = 0; i < _dias.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(rotuloDoDia(_dias[i], i)),
                    selected: _dias[i] == _dia,
                    onSelected: (_) => _escolherDia(_dias[i]),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<_Carga>(
            future: _carga,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final carga = snap.data;
              if (carga == null) {
                return _mensagem('Não deu para carregar. Confira a internet do celular.');
              }
              return _grade(carga);
            },
          ),
        ),
      ],
    );
  }

  Widget _grade(_Carga carga) {
    final tema = Theme.of(context);
    return CustomScrollView(
      slivers: [
        if (carga.falhas > 0)
          SliverToBoxAdapter(
            child: ListTile(
              dense: true,
              leading: Icon(Icons.info_outline, color: tema.colorScheme.onSurfaceVariant),
              title: Text(
                carga.falhas == 1
                    ? 'As fotos de 1 PC não carregaram. Confira a internet do celular.'
                    : 'As fotos de ${carga.falhas} PCs não carregaram. Confira a internet do celular.',
              ),
            ),
          ),
        if (carga.fotos.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _mensagem(
              'Nenhuma foto de início de sessão neste dia.\n\n'
              'Elas aparecem nos PCs com Celita OS 1.30 ou mais novo. As mais '
              'antigas continuam no histórico de cada PC.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _tile(carga.fotos[i]),
                childCount: carga.fotos.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(FotoDeEntrada f) {
    final tema = Theme.of(context);
    final pc = widget.deviceId == null ? _nomeDoPc(f.deviceId) : null;
    return FutureBuilder<ArchivedPhoto>(
      future: _foto(f),
      builder: (context, snap) {
        final foto = snap.data;
        final legenda = [
          _hora(f.ref.ts),
          if (pc != null) pc,
          if (foto?.user != null && foto!.user!.isNotEmpty) foto.user!,
        ].join(' · ');
        return Semantics(
          button: true,
          label: 'Início de sessão: $legenda',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _abrir(f),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: tema.colorScheme.surfaceContainerHighest,
                    child: foto != null
                        ? Image.memory(foto.jpeg, fit: BoxFit.cover, cacheWidth: 400, gaplessPlayback: true)
                        : snap.hasError
                            ? Icon(Icons.broken_image_outlined, color: tema.colorScheme.onSurfaceVariant)
                            : const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                      child: Text(
                        legenda,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
