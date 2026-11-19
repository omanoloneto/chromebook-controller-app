// Galeria das telas: uma foto da tela de cada computador ligado, duas por
// linha, com o nome da unidade ou do aluno. Abre grande e salva uma ou todas.
// Serve ao professor e à monitora: cada um diz como lista e como captura.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/conversa.dart' show quemEscreveu;
import '../pairing/monitora_controller.dart';
import '../pairing/pairing_controller.dart';
import 'componentes.dart';
import 'visualizador.dart';

class TelaNaGaleria {
  const TelaNaGaleria({required this.id, required this.rotulo});

  final String id;

  /// "Unidade 7" ou, com aluno da chamada, "Ana Lima · 3º ano".
  final String rotulo;
}

/// Quantas capturas pedir ao mesmo tempo: a sala inteira de uma vez pesa no
/// Wi-Fi da escola.
const int kCapturasJuntas = 4;

class _Foto {
  Uint8List? jpeg;
  int? ts;
  bool buscando = false;
  bool falhou = false;
}

class GaleriaDeTelas extends StatefulWidget {
  const GaleriaDeTelas({
    super.key,
    required this.pcsLigados,
    required this.capturar,
    this.agoraMs,
  });

  final List<TelaNaGaleria> Function() pcsLigados;

  /// null = o PC não respondeu ou recusou.
  final Future<Uint8List?> Function(String id) capturar;
  final int Function()? agoraMs;

  @override
  State<GaleriaDeTelas> createState() => _GaleriaDeTelasState();
}

class _GaleriaDeTelasState extends State<GaleriaDeTelas> {
  List<TelaNaGaleria> _pcs = const [];
  final Map<String, _Foto> _fotos = {};
  bool _salvando = false;

  int get _agora => widget.agoraMs?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _pcs = widget.pcsLigados();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_atualizar());
    });
  }

  Future<void> _atualizar() async {
    setState(() {
      _pcs = widget.pcsLigados();
      for (final pc in _pcs) {
        (_fotos[pc.id] ??= _Foto())
          ..buscando = true
          ..falhou = false;
      }
    });
    final fila = [..._pcs];
    Future<void> trabalhar() async {
      while (fila.isNotEmpty) {
        final pc = fila.removeAt(0);
        Uint8List? jpeg;
        try {
          jpeg = await widget.capturar(pc.id);
        } catch (_) {
          jpeg = null;
        }
        if (!mounted) return;
        setState(() {
          final f = _fotos[pc.id]!..buscando = false;
          if (jpeg != null) {
            f
              ..jpeg = jpeg
              ..ts = _agora;
          } else {
            f.falhou = true;
          }
        });
      }
    }

    await Future.wait([for (var i = 0; i < kCapturasJuntas; i++) trabalhar()]);
  }

  String _nomeDoArquivo(TelaNaGaleria pc) => nomeParaGaleria(pc.rotulo, _fotos[pc.id]?.ts ?? _agora);

  void _avisar(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _salvarUma(TelaNaGaleria pc) async {
    final jpeg = _fotos[pc.id]?.jpeg;
    if (jpeg == null) return;
    final erro = await salvarImagemNaGaleria(jpeg, _nomeDoArquivo(pc));
    if (!mounted) return;
    _avisar(erro ?? 'Tela salva $destinoDoSalvar.');
  }

  Future<void> _salvarTodas() async {
    final prontas = [for (final pc in _pcs) if (_fotos[pc.id]?.jpeg != null) pc];
    if (prontas.isEmpty) return;
    setState(() => _salvando = true);
    var salvas = 0;
    String? erro;
    for (final pc in prontas) {
      final e = await salvarImagemNaGaleria(_fotos[pc.id]!.jpeg!, _nomeDoArquivo(pc));
      if (e == null) {
        salvas++;
      } else {
        erro ??= e;
      }
    }
    if (!mounted) return;
    setState(() => _salvando = false);
    final total = prontas.length;
    _avisar(
      erro != null && salvas == 0 ? erro : '$salvas de $total ${total == 1 ? 'tela salva' : 'telas salvas'} $destinoDoSalvar.',
    );
  }

  Future<void> _abrir(TelaNaGaleria pc) async {
    final jpeg = _fotos[pc.id]?.jpeg;
    if (jpeg == null) return;
    await abrirImagem(context, bytes: jpeg, titulo: pc.rotulo, nomeArquivo: _nomeDoArquivo(pc));
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _pcs.any((pc) => _fotos[pc.id]?.buscando ?? false);
    final algumaPronta = _pcs.any((pc) => _fotos[pc.id]?.jpeg != null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telas dos computadores'),
        actions: [
          IconButton(
            tooltip: 'Baixar todas',
            onPressed: algumaPronta && !_salvando ? _salvarTodas : null,
            icon: _salvando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Tirar de novo',
            onPressed: buscando ? null : _atualizar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _pcs.isEmpty
          ? const EstadoVazio(
              icone: Icons.desktop_access_disabled_outlined,
              titulo: 'Nenhum computador ligado',
              texto: 'As telas aparecem aqui quando os computadores estão ligados.',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              itemCount: _pcs.length,
              itemBuilder: (context, i) => _cartao(_pcs[i]),
            ),
    );
  }

  Widget _cartao(TelaNaGaleria pc) {
    final t = Theme.of(context);
    final f = _fotos[pc.id];
    final jpeg = f?.jpeg;
    return Material(
      color: t.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: jpeg == null ? null : () => _abrir(pc),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (jpeg != null)
                    Image.memory(jpeg, fit: BoxFit.cover, gaplessPlayback: true)
                  else
                    Center(
                      child: f?.falhou ?? false
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Sem resposta',
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodySmall,
                              ),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  if (jpeg != null && (f?.buscando ?? false))
                    const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
                ],
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pc.rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Baixar',
                  visualDensity: VisualDensity.compact,
                  onPressed: jpeg == null ? null : () => _salvarUma(pc),
                  icon: const Icon(Icons.download_outlined, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Galeria do professor: PCs ligados (menos o telão), em ordem de unidade; com
/// aluno da chamada, o nome e o ano da turma no lugar do número.
Future<void> abrirGaleriaDoProfessor(BuildContext context, PairingController p) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GaleriaDeTelas(
          agoraMs: p.agoraServidorMs,
          pcsLigados: () {
            final ligados = [
              for (final s in p.pcs)
                if (p.isOnline(s) && !p.ehPcProfessor(s.deviceId)) s,
            ]..sort((a, b) => (p.numeroDe(a.deviceId) ?? 1 << 30).compareTo(p.numeroDe(b.deviceId) ?? 1 << 30));
            return [
              for (final s in ligados)
                TelaNaGaleria(
                  id: s.deviceId,
                  rotulo: quemEscreveu(p.alunoDe(s.deviceId), p.anoDaTurmaDaAula) ?? p.nomeDe(s),
                ),
            ];
          },
          capturar: p.tirarFotoTela,
        ),
      ),
    );

/// Galeria da monitora: pelo canal dela; o nome do aluno vem do próprio PC.
Future<void> abrirGaleriaDaMonitora(BuildContext context, MonitoraController c) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GaleriaDeTelas(
          agoraMs: () => c.agoraMs,
          pcsLigados: () => [
            for (final pc in c.pcs)
              if (c.ligado(pc)) TelaNaGaleria(id: pc.id, rotulo: pc.rotulo),
          ],
          capturar: (id) async {
            final pc = c.pcs.where((p) => p.id == id).firstOrNull;
            return pc == null ? null : (await c.verTela(pc)).jpeg;
          },
        ),
      ),
    );
