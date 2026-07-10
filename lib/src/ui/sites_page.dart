// Aba Sites: Favoritos e Regras num só lugar (tabs). FAB contextual.
// As Views são burras; os dialogs de criar/editar vivem aqui.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../pairing/pairing_controller.dart';
import 'favorites_page.dart';
import 'rules_page.dart';

class SitesPage extends StatefulWidget {
  const SitesPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
    _tabs.addListener(_onChange); // troca o FAB junto com a aba
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ---- Dialogs (criar/editar) -----------------------------------------------------

  Future<void> _dialogoFavorito({int? indice}) async {
    final itens = widget.pairing.favoritos;
    final existente = indice != null ? itens[indice] : null;
    final labelCtrl = TextEditingController(text: existente?.label ?? '');
    final urlCtrl = TextEditingController(text: existente?.url ?? 'https://');
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Novo favorito' : 'Editar favorito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'ex.: Khan — Frações',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Endereço',
                hintText: 'https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salvo != true || urlCtrl.text.trim().isEmpty) return;
    if (indice == null) {
      await widget.pairing.adicionarFavorito(labelCtrl.text, urlCtrl.text);
    } else {
      await widget.pairing.editarFavorito(indice, labelCtrl.text, urlCtrl.text);
    }
  }

  Future<void> _dialogoRegra({int? indice}) async {
    final regras = widget.pairing.regras;
    final existente = indice != null ? regras[indice] : null;
    final ctrl = TextEditingController(text: existente?.pattern ?? '');
    var action = existente?.action ?? RuleAction.block;
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existente == null ? 'Nova regra' : 'Editar regra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Domínio ou prefixo',
                  hintText: 'ex.: youtube.com ou reddit.com/r/jogos',
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: RuleAction.block,
                    label: Text('Bloquear'),
                    icon: Icon(Icons.block),
                  ),
                  ButtonSegment(
                    value: RuleAction.alert,
                    label: Text('Alertar'),
                    icon: Icon(Icons.warning_amber),
                  ),
                ],
                selected: {action},
                onSelectionChanged: (sel) =>
                    setDialogState(() => action = sel.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (salvo != true || ctrl.text.trim().isEmpty) return;
    if (indice == null) {
      await widget.pairing.adicionarRegra(ctrl.text, action);
    } else {
      await widget.pairing.atualizarRegra(indice, ctrl.text, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sites'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.star_outline), text: 'Favoritos'),
            Tab(icon: Icon(Icons.shield_outlined), text: 'Regras'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_sites',
        onPressed: () => _tabs.index == 0 ? _dialogoFavorito() : _dialogoRegra(),
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'Novo favorito' : 'Nova regra'),
      ),
      body: TabBarView(
        controller: _tabs,
        // Sem swipe de página: não briga com o swipe-para-apagar das listas.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          FavoritesView(pairing: widget.pairing, onEditar: (i) => _dialogoFavorito(indice: i)),
          RulesView(pairing: widget.pairing, onEditar: (i) => _dialogoRegra(indice: i)),
        ],
      ),
    );
  }
}
