// Histórico de 15 dias de um PC do Celita OS (vem da nuvem, não da memória):
// sites por dia, agrupados por entrada na conta, e a foto da câmera mais
// próxima de cada site.

import 'package:flutter/material.dart';

import '../cloud/archive_store.dart';
import '../pairing/pairing_controller.dart';
import '../secure/crypto.dart';
import '../util/versao.dart';
import 'device_page.dart';
import 'theme.dart';

const _diasDaSemana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// Rótulo do seletor: "Hoje", "Ontem" ou "qua 23/09".
String rotuloDoDia(String dia, int indice) {
  if (indice == 0) return 'Hoje';
  if (indice == 1) return 'Ontem';
  final d = DateTime.parse('${dia}T00:00:00Z');
  return '${_diasDaSemana[d.weekday - 1]} ${dia.substring(8, 10)}/${dia.substring(5, 7)}';
}

String _hora(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String? _motivo(String? m) => switch (m) {
      'login' => 'ao entrar na conta',
      'periodica' => 'foto de rotina (a cada 30 min)',
      'bloqueado' => 'na tentativa de abrir um site bloqueado',
      'alerta' => 'ao abrir um site com aviso',
      _ => null,
    };

/// "1 min depois deste site", "2 h 5 min antes deste site"...
String distanciaDaFoto(int fotoTs, int siteTs) {
  final diff = fotoTs - siteTs;
  final min = (diff.abs() / 60000).round();
  if (min == 0) return 'no mesmo minuto deste site';
  final h = min ~/ 60;
  final m = min % 60;
  final tempo = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
  return '$tempo ${diff > 0 ? 'depois' : 'antes'} deste site';
}

/// "Foto das HH:MM — <motivo> · conta <user>" + a distância até o site.
String legendaDaFoto(ArchivedPhoto foto, int siteTs) {
  final motivo = _motivo(foto.motivo);
  final user = foto.user;
  final partes = [
    'Foto das ${_hora(foto.ts)}',
    if (motivo != null) ' — $motivo',
    if (user != null && user.isNotEmpty) ' · conta $user',
  ];
  return '${partes.join()}\n${distanciaDaFoto(foto.ts, siteTs)}';
}

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.pairing, required this.deviceId});

  final PairingController pairing;
  final String deviceId;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late final List<String> _dias = recentDays(widget.pairing.agoraServidorMs());
  late final ArchiveStore? _store = widget.pairing.arquivoDe(widget.deviceId);
  late String _dia = _dias.first;
  Future<ArchivedDay>? _carga;

  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
    _carga = _store?.readDay(_dia);
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _carregar() {
    final store = _store;
    if (store == null) return;
    setState(() => _carga = store.readDay(_dia));
  }

  void _escolherDia(String dia) {
    if (dia == _dia) return;
    _dia = dia;
    _carregar();
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _verFoto(
    ArchivedSession sessao,
    ArchivedNavEvent evento,
    String nome,
  ) async {
    final store = _store;
    if (store == null) return;
    final dia = _dia;
    ChosenPhoto? escolhida;
    String? erro;
    try {
      escolhida = await esperarComSpinner(
        context,
        'Buscando a foto…',
        store.photoFor(dia, sessao, evento),
      );
      if (escolhida == null) erro = 'Nenhuma foto deste horário.';
    } on PhotoException catch (e) {
      erro = switch (e.failure) {
        PhotoFailure.deleted =>
          'Esta foto já foi apagada (as fotos ficam guardadas 15 dias).',
        PhotoFailure.unreadable => 'Não dá para abrir esta foto.',
        PhotoFailure.download =>
          'Não deu para baixar a foto. Confira a internet do celular e tente de novo.',
      };
    } catch (_) {
      erro = 'Não deu para baixar a foto. Confira a internet do celular e tente de novo.';
    }
    if (!mounted || !continuaNaFrente(context)) return;
    if (escolhida == null) {
      _snack(erro ?? 'Nenhuma foto deste horário.');
      return;
    }
    await mostrarDialogoImagem(
      context,
      bytes: escolhida.photo.jpeg,
      titulo: 'Quem estava no PC — $nome',
      legenda: legendaDaFoto(escolhida.photo, evento.ts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.pairing.pcPorId(widget.deviceId);
    final nome = s != null ? widget.pairing.nomeDe(s) : 'PC';
    return Scaffold(
      appBar: AppBar(title: Text('Histórico — $nome')),
      body: _corpo(nome),
    );
  }

  Widget _mensagem(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      );

  Widget _corpo(String nome) {
    final s = widget.pairing.pcPorId(widget.deviceId);
    if (s == null || _store == null) {
      return _mensagem('Este PC não está mais conectado.');
    }
    if (!temCelita(s.versaoExt)) {
      return _mensagem(
        'O histórico guardado e as fotos existem só nos PCs com Celita OS.',
      );
    }
    if (!widget.pairing.workspaceAtivo) {
      return _mensagem(
        'O histórico guardado e as fotos existem só nos PCs da escola.',
      );
    }
    final offline = !widget.pairing.isOnline(s);
    return Column(
      children: [
        if (offline)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text(
              'Este PC está desligado. Os últimos minutos de uso aparecem '
              'quando ele ligar de novo.',
            ),
          ),
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
        Divider(height: 1, color: hairline(Theme.of(context).brightness)),
        Expanded(
          child: FutureBuilder<ArchivedDay>(
            future: _carga,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || !snap.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Não deu para carregar. Confira a internet do celular.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _carregar,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar de novo'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return _lista(snap.data!, nome);
            },
          ),
        ),
      ],
    );
  }

  Widget _lista(ArchivedDay dia, String nome) {
    final tema = Theme.of(context);
    final apagado = tema.colorScheme.onSurfaceVariant;
    return ListView(
      children: [
        if (dia.unreadable > 0)
          ListTile(
            dense: true,
            leading: Icon(Icons.info_outline, color: apagado),
            title: const Text('Parte do histórico deste dia não pôde ser aberta.'),
          ),
        if (dia.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Nenhum site visitado neste dia.',
              textAlign: TextAlign.center,
              style: TextStyle(color: apagado),
            ),
          ),
        for (final sessao in dia.sessions)
          if (sessao.events.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Conta ${sessao.user} · entrou às ${_hora(sessao.login)}',
                style: tema.textTheme.labelLarge?.copyWith(
                  color: tema.colorScheme.primary,
                ),
              ),
            ),
            for (final e in sessao.events) _item(sessao, e, nome),
          ],
      ],
    );
  }

  Widget _item(ArchivedSession sessao, ArchivedNavEvent e, String nome) {
    return ListTile(
      dense: true,
      leading: Text(
        _hora(e.ts),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      title: Text(
        e.title.isEmpty ? dominioDe(e.url) : e.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (e.action != null) ...[
            _selo(e.action!),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              dominioDe(e.url),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opções do site',
        onSelected: (v) {
          if (v == 'foto') _verFoto(sessao, e, nome);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'foto',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.photo_camera_outlined),
              title: Text('Ver quem estava no PC na hora'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selo(String acao) {
    final bloqueado = acao == 'bloqueado';
    final cor = bloqueado ? Theme.of(context).colorScheme.error : cores(context).atencao;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: cor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        bloqueado ? 'Bloqueado' : 'Aviso',
        style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
