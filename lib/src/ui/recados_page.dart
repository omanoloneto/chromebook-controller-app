// Recados dos alunos (item 27 + chat): uma lista com pedidos de liberação,
// mãos levantadas e conversas, nesta ordem. "Liberar" tira as regras que
// casam o site pedido (ou, em prova, libera o site naquele PC); "Recusar"
// manda o motivo ao aluno. Ver SPEC-turma §4.4.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/conversa.dart';
import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import 'chat_page.dart';
import 'theme.dart';

/// Nome de rota de Recados (o toque numa notificação de pedido volta a ela).
const String rotaDosRecados = '/recados';

Route<void> rotaRecadosPage(PairingController pairing) => MaterialPageRoute(
      settings: const RouteSettings(name: rotaDosRecados),
      builder: (_) => RecadosPage(pairing: pairing),
    );

/// Abre Recados (sem empilhar outra igual em cima).
void abrirRecados(BuildContext context, PairingController pairing) {
  final nav = Navigator.of(context);
  var jaNoTopo = false;
  nav.popUntil((r) {
    jaNoTopo = r.settings.name == rotaDosRecados;
    return true;
  });
  if (jaNoTopo) return;
  nav.push(rotaRecadosPage(pairing));
}

class RecadosPage extends StatefulWidget {
  const RecadosPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<RecadosPage> createState() => _RecadosPageState();
}

class _RecadosPageState extends State<RecadosPage> {
  PairingController get _p => widget.pairing;

  // Mão some sozinha depois de 10 min; o silêncio vence em 10 min.
  Timer? _relogio;

  // Pedidos com Liberar/Recusar em andamento (sem toque duplo).
  final Set<PedidoLiberacao> _ocupados = Set.identity();

  @override
  void initState() {
    super.initState();
    _p.addListener(_onChange);
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) => _onChange());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _p.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _liberar(PedidoLiberacao pedido) async {
    final nome = _p.nomeDoPc(pedido.deviceId);
    List<String>? padroes;
    if (!_p.provaNoPc(pedido.deviceId)) {
      padroes = _p.padroesParaLiberar(pedido);
      if (padroes.length > 1) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Liberar para $nome: ${padroes!.join(', ')}?'),
            content: const Text(
              'O site pedido é bloqueado por mais de uma regra. Todas elas '
              'deixam de valer neste computador até você bloquear de novo ou '
              'encerrar a aula.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Liberar'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    setState(() => _ocupados.add(pedido));
    final erro = await _p.liberarPedido(pedido, padroes: padroes);
    if (!mounted) return;
    setState(() => _ocupados.remove(pedido));
    _snack(erro ?? '${pedido.site} liberado para $nome.');
  }

  Future<void> _recusar(PedidoLiberacao pedido) async {
    final motivo = await mostrarDialogoRecusar(context);
    if (motivo == null || !mounted) return;
    setState(() => _ocupados.add(pedido));
    final erro = await _p.recusarPedido(
      pedido,
      motivo: motivo.trim().isEmpty ? null : motivo.trim(),
    );
    if (!mounted) return;
    setState(() => _ocupados.remove(pedido));
    _snack(erro ?? 'Pedido recusado.');
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = _p.pedidosPendentes;
    final maos = _p.maosLevantadas;
    final conversas = _p.conversas;
    final silenciados = _p.pcsSilenciados;
    final vazio = pedidos.isEmpty &&
        maos.isEmpty &&
        conversas.isEmpty &&
        silenciados.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Recados')),
      body: vazio
          ? _vazio()
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (pedidos.isNotEmpty) ...[
                  _Titulo('Pedidos de liberação', pedidos.length),
                  for (final p in pedidos) _pedido(p),
                ],
                if (maos.isNotEmpty) ...[
                  _Titulo('Mãos levantadas', maos.length),
                  for (final s in maos) _mao(s),
                ],
                if (conversas.isNotEmpty) ...[
                  _Titulo('Conversas', conversas.length),
                  for (final s in conversas) _conversa(s),
                ],
                for (final id in silenciados) _silenciado(id),
              ],
            ),
    );
  }

  Widget _vazio() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            const Text(
              'Nenhum recado dos alunos agora.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pedido(PedidoLiberacao p) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final ocupado = _ocupados.contains(p);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline(Theme.of(context).brightness)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_p.nomeDoPc(p.deviceId)} · ${horaMinuto(p.ts)}',
                style:
                    texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                p.site,
                style: texto.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (p.motivo.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '“${p.motivo}”',
                  style:
                      texto.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (ocupado)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton(
                    onPressed: ocupado ? null : () => _recusar(p),
                    child: const Text('Recusar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: ocupado ? null : () => _liberar(p),
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Liberar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mao(PcSession s) {
    final c = cores(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.atencao.withValues(alpha: 0.16),
        child: Icon(Icons.back_hand, color: c.atencao),
      ),
      title: Text(
        '${_p.nomeDoPc(s.deviceId)} levantou a mão · ${horaMinuto(s.maoEm!)}',
      ),
      onTap: () => abrirConversa(context, _p, s.deviceId),
      trailing: TextButton(
        onPressed: () => _p.baixarMao(s.deviceId),
        child: const Text('Baixar'),
      ),
    );
  }

  Widget _conversa(PcSession s) {
    final scheme = Theme.of(context).colorScheme;
    final nome = _p.nomeDoPc(s.deviceId);
    final ultima = s.chat.last;
    final previa = switch (ultima.autor) {
      AutorChat.professor => 'Você: ${ultima.texto}',
      _ => ultima.texto,
    };
    final naoLidas = s.naoLidas;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          iniciaisDe(nome),
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        nome,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: naoLidas > 0 ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        previa.replaceAll('\n', ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: naoLidas > 0 ? TextStyle(color: scheme.onSurface) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            horaMinuto(ultima.ts),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      naoLidas > 0 ? scheme.primary : scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          if (naoLidas > 0) Badge.count(count: naoLidas),
        ],
      ),
      onTap: () => abrirConversa(context, _p, s.deviceId),
    );
  }

  Widget _silenciado(String deviceId) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.speaker_notes_off_outlined,
          color: scheme.onSurfaceVariant,
        ),
      ),
      title: Text(_p.nomeDoPc(deviceId)),
      subtitle: const Text(kTextoSilenciado),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, this.n);

  final String texto;
  final int n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        '$texto ($n)',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

/// Diálogo "Recusar o pedido?" com o motivo opcional (≤ 200). Devolve o
/// motivo (vazio = sem motivo) ou null se o professor cancelou.
Future<String?> mostrarDialogoRecusar(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Recusar o pedido?'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 200,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Motivo (opcional)',
          hintText: 'Ex.: Depois da prova.',
          helperText: 'O aluno vê o motivo.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Recusar'),
        ),
      ],
    ),
  );
}
