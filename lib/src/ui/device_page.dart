// Tela de detalhe de um PC: aba ativa, abas abertas e histórico de navegação
// (somente URLs/títulos — sem captura de tela; dados ficam em memória).

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';

/// Domínio de uma URL para exibição compacta ("pt.khanacademy.org").
String dominioDe(String url) {
  try {
    final host = Uri.parse(url).host;
    return host.isEmpty ? url : host;
  } catch (_) {
    return url;
  }
}

/// Diálogo de renomear (usado aqui e na home via long-press).
Future<void> mostrarDialogoRenomear(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nomeAtual,
) async {
  final ctrl = TextEditingController(text: nomeAtual);
  final novo = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nome do aluno'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Ex.: Maria (fundo da sala)',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  if (novo != null) await pairing.renomear(deviceId, novo);
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.pairing, required this.deviceId});

  final PairingController pairing;
  final String deviceId;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
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

  String _hora(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _fecharPorDominio(String url) async {
    final dominio = dominioDe(url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar site neste PC'),
        content: Text('Fechar todas as abas de $dominio neste PC?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.pairing.fecharSiteEm(widget.deviceId, dominio);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Fechando $dominio…')));
    }
  }

  String _atualizadoHa(DateTime? t) {
    if (t == null) return 'sem dados de abas ainda';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'Atualizado há ${s}s';
    return 'Atualizado há ${s ~/ 60}min';
  }

  // Liberar/revogar padrões bloqueados só para este PC, só nesta aula.
  Future<void> _liberarSites() async {
    final padroes = widget.pairing.padroesBloqueio;
    if (padroes.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Nenhum site bloqueado nas regras.')),
        );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final liberados = widget.pairing.liberacoesDe(widget.deviceId);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('Liberar sites para este PC'),
                  subtitle: Text('Vale só até o fim da aula.'),
                ),
                const Divider(height: 1),
                for (final p in padroes)
                  SwitchListTile(
                    title: Text(p),
                    subtitle: Text(
                      liberados.contains(p) ? 'LIBERADO nesta aula' : 'bloqueado',
                    ),
                    value: liberados.contains(p),
                    onChanged: (ligar) async {
                      if (ligar) {
                        await widget.pairing.liberarPara(widget.deviceId, p);
                      } else {
                        await widget.pairing
                            .revogarLiberacao(widget.deviceId, p);
                      }
                      setSheet(() {});
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmarFecharTudo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar todas as abas'),
        content: const Text(
          'Fechar TODAS as abas deste PC? Ele fica com uma aba vazia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fechar tudo'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.pairing.fecharTodasAsAbasEm(widget.deviceId);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fechando todas as abas…')));
    }
  }

  Future<void> _confirmarEsquecer(String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esquecer este PC'),
        content: Text(
          'Desfazer o vínculo com "$nome"?\n\n'
          'O Chromebook volta a exibir o QR de pareamento e some da sua lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Esquecer'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.pairing.esquecerPc(widget.deviceId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.pairing.pcPorId(widget.deviceId);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PC desconectado')),
        body: const Center(child: Text('Este PC não está mais vinculado.')),
      );
    }
    final nome = widget.pairing.nomeDe(s);
    final on = widget.pairing.isOnline(s);
    final ativa = s.abaAtiva;
    final historico = s.history.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(nome),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Renomear',
            onPressed: () => mostrarDialogoRenomear(
              context,
              widget.pairing,
              widget.deviceId,
              nome,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Esquecer este PC',
            onPressed: () => _confirmarEsquecer(nome),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (on && s.alerta != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Alerta: aba de ${s.alerta} aberta')),
                ],
              ),
            ),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: on ? const Color(0xFF00897B) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(on ? 'online' : 'offline'),
              const Spacer(),
              Text(
                _atualizadoHa(s.lastReportAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          if (widget.pairing.aulaAtiva) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.pairing.alunoDe(widget.deviceId) ??
                        'Nenhum aluno vinculado nesta aula',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _liberarSites,
              icon: const Icon(Icons.lock_open),
              label: Text(
                widget.pairing.liberacoesDe(widget.deviceId).isEmpty
                    ? 'Liberar sites para este PC (nesta aula)'
                    : 'Sites liberados: '
                        '${widget.pairing.liberacoesDe(widget.deviceId).length} '
                        '(toque para gerenciar)',
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: on ? _confirmarFecharTudo : null,
            icon: const Icon(Icons.tab_unselected),
            label: const Text('Fechar todas as abas deste PC'),
          ),
          const SizedBox(height: 16),
          Text('Aba ativa', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ativa == null
                  ? const Text('Sem aba ativa informada.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ativa.title.isEmpty ? '(sem título)' : ativa.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          ativa.url,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Abas abertas (${s.tabs.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          if (s.tabs.isEmpty)
            const ListTile(dense: true, title: Text('Nenhuma aba informada.')),
          for (final t in s.tabs)
            ListTile(
              dense: true,
              leading: Icon(
                t.active ? Icons.tab : Icons.tab_unselected,
                color: t.active ? const Color(0xFF00897B) : Colors.grey,
              ),
              title: Text(
                t.title.isEmpty ? '(sem título)' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(dominioDe(t.url)),
              onLongPress: () => _fecharPorDominio(t.url),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar esta aba',
                onPressed: () {
                  widget.pairing.fecharAbaEm(widget.deviceId, t.url);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Fechando a aba…')),
                    );
                },
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Histórico de navegação',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          if (historico.isEmpty)
            const ListTile(dense: true, title: Text('Nenhuma visita ainda.')),
          for (final e in historico)
            ListTile(
              dense: true,
              leading: Text(
                _hora(e.ts),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              title: Text(
                e.title.isEmpty ? e.url : e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(dominioDe(e.url)),
            ),
        ],
      ),
    );
  }
}
