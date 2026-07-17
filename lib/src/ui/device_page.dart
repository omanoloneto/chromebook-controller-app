// Tela de detalhe de um PC: aba ativa, abas abertas e histórico de navegação
// (somente URLs/títulos — sem captura de tela; dados ficam em memória).

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import 'theme.dart';

/// Domínio de uma URL para exibição compacta ("pt.khanacademy.org").
String dominioDe(String url) {
  try {
    final host = Uri.parse(url).host;
    return host.isEmpty ? url : host;
  } catch (_) {
    return url;
  }
}

/// Sheet de liberação de sites bloqueados p/ UM PC (usado aqui e no menu ⋮
/// da aba Aula). Exige aula ativa — a liberação morre no "Encerrar aula".
Future<void> mostrarSheetLiberarSites(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!pairing.aulaAtiva) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Inicie uma aula para liberar sites — a liberação vale só até o '
            'fim da aula.',
          ),
        ),
      );
    return;
  }
  final padroes = pairing.padroesBloqueio;
  if (padroes.isEmpty) {
    messenger
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
        final liberados = pairing.liberacoesDe(deviceId);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Desbloquear sites para este PC'),
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
                      await pairing.liberarPara(deviceId, p);
                    } else {
                      await pairing.revogarLiberacao(deviceId, p);
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

/// Confirmação de "Esquecer este PC" (usada aqui e no menu ⋮ da aba Aula).
/// Retorna true se desvinculou.
Future<bool> confirmarEsquecerPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
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
  if (ok == true) {
    await pairing.esquecerPc(deviceId);
    return true;
  }
  return false;
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

/// Diálogo de alterar o número da unidade (aqui e no menu da aba Aula).
Future<void> mostrarDialogoNumeroUnidade(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final atual = pairing.numeroDe(deviceId);
  final ctrl = TextEditingController(text: atual?.toString() ?? '');
  final texto = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Número da unidade'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: 'Ex.: 7',
          helperText: 'Se o número já for de outro PC, os dois trocam.',
          helperMaxLines: 2,
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
  if (texto == null || !context.mounted) return;
  final numero = int.tryParse(texto.trim());
  final erro = numero == null
      ? 'Digite um número de 1 a 9999.'
      : await pairing.alterarNumeroUnidade(deviceId, numero);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(erro ?? 'Agora é a Unidade $numero.')),
  );
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

  Future<void> _liberarSites() =>
      mostrarSheetLiberarSites(context, widget.pairing, widget.deviceId);

  void _abrirNoTelao(String url) {
    widget.pairing.abrirNoPcProfessor(url);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Abrindo no PC do professor…')),
      );
  }

  /// Item de menu "Abrir no PC do professor" (usado na aba ativa, nas abas
  /// abertas e no histórico). Desabilitado explica o porquê.
  PopupMenuItem<String> _itemMenuTelao() {
    return PopupMenuItem(
      value: 'telao',
      enabled: widget.pairing.pcProfessorOnline,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.co_present),
        title: const Text('Abrir no PC do professor'),
        subtitle: widget.pairing.pcProfessorOnline
            ? null
            : Text(
                widget.pairing.pcProfessorId == null
                    ? 'nenhum PC marcado como do professor'
                    : 'PC do professor está offline',
              ),
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
    final saiu = await confirmarEsquecerPc(
      context,
      widget.pairing,
      widget.deviceId,
      nome,
    );
    if (saiu && mounted) Navigator.of(context).pop();
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
          // Ação destrutiva fora da barra: evita toque acidental.
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (v) {
              if (v == 'numero') {
                mostrarDialogoNumeroUnidade(
                  context,
                  widget.pairing,
                  widget.deviceId,
                );
              }
              if (v == 'esquecer') _confirmarEsquecer(nome);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'numero',
                child: ListTile(
                  leading: Icon(Icons.pin),
                  title: Text('Alterar número da unidade'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'esquecer',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Esquecer este PC'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
                color: cores(context).alertaBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: cores(context).alertaFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alerta: aba de ${s.alerta} aberta',
                      style: TextStyle(color: cores(context).alertaFg),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: on ? cores(context).online : cores(context).offline,
              ),
              const SizedBox(width: 8),
              Text(on ? 'online' : 'offline'),
              const Spacer(),
              Text(
                _atualizadoHa(s.lastReportAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _liberarSites,
                  icon: const Icon(Icons.lock_open),
                  label: Text(
                    widget.pairing.liberacoesDe(widget.deviceId).isEmpty
                        ? 'Desbloquear sites'
                        : 'Liberados: '
                            '${widget.pairing.liberacoesDe(widget.deviceId).length}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: on ? _confirmarFecharTudo : null,
                  icon: const Icon(Icons.tab_unselected),
                  label: const Text('Fechar abas'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Aba ativa', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ativa == null
                  ? const Text('Sem aba ativa informada.')
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ativa.title.isEmpty
                                    ? '(sem título)'
                                    : ativa.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
                        PopupMenuButton<String>(
                          tooltip: 'Opções da aba ativa',
                          onSelected: (v) {
                            if (v == 'telao') _abrirNoTelao(ativa.url);
                          },
                          itemBuilder: (_) => [_itemMenuTelao()],
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
                color: t.active
                    ? cores(context).online
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(
                t.title.isEmpty ? '(sem título)' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(dominioDe(t.url)),
              // Long-press = atalho; o menu ⋮ é a affordance visível.
              onLongPress: () => _fecharPorDominio(t.url),
              trailing: PopupMenuButton<String>(
                tooltip: 'Opções da aba',
                onSelected: (v) {
                  if (v == 'aba') {
                    widget.pairing.fecharAbaEm(widget.deviceId, t.url);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Fechando a aba…')),
                      );
                  } else if (v == 'dominio') {
                    _fecharPorDominio(t.url);
                  } else if (v == 'telao') {
                    _abrirNoTelao(t.url);
                  }
                },
                itemBuilder: (_) => [
                  _itemMenuTelao(),
                  const PopupMenuItem(
                    value: 'aba',
                    child: Text('Fechar esta aba'),
                  ),
                  PopupMenuItem(
                    value: 'dominio',
                    child: Text('Fechar todas de ${dominioDe(t.url)}'),
                  ),
                ],
              ),
            ),
          if (!widget.pairing.ehPcProfessor(widget.deviceId)) ...[
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
                trailing: PopupMenuButton<String>(
                  tooltip: 'Opções do link',
                  onSelected: (v) {
                    if (v == 'telao') _abrirNoTelao(e.url);
                  },
                  itemBuilder: (_) => [_itemMenuTelao()],
                ),
              ),
          ] else ...[
            const SizedBox(height: 16),
            const ListTile(
              dense: true,
              leading: Icon(Icons.co_present),
              title: Text('PC do professor'),
              subtitle: Text(
                'Sem monitoramento de histórico, alertas ou bloqueios.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
