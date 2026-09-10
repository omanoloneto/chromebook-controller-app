// Aba Sites: Favoritos, Regras e a Página inicial dos alunos (tabs). FAB
// contextual.
// As Views são burras; os dialogs de criar/editar vivem aqui.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../pairing/pairing_controller.dart';
import '../pairing/home_store.dart';
import 'favorites_page.dart';
import 'home_page_view.dart';
import 'rules_page.dart';

class SitesPage extends StatefulWidget {
  const SitesPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

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

  Future<void> _dialogoAtalho({int? indice}) async {
    final atalhos = widget.pairing.paginaInicial.atalhos;
    final existente = indice != null ? atalhos[indice] : null;
    final labelCtrl = TextEditingController(text: existente?.label ?? '');
    final urlCtrl = TextEditingController(text: existente?.url ?? 'https://');
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Novo atalho' : 'Editar atalho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              maxLength: kMaxLabelHome,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'ex.: Drive',
              ),
            ),
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
    if (salvo != true) return;
    final aceito = indice == null
        ? await widget.pairing.adicionarAtalhoDaPagina(labelCtrl.text, urlCtrl.text)
        : await widget.pairing.editarAtalhoDaPagina(indice, labelCtrl.text, urlCtrl.text);
    if (!aceito && mounted) {
      final cheia = indice == null &&
          widget.pairing.paginaInicial.atalhos.length >= kMaxAtalhosHome;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cheia
                ? 'A página comporta $kMaxAtalhosHome atalhos. Remova um antes.'
                : 'Endereço inválido. Ele precisa começar com https:// ou http://',
          ),
        ),
      );
    }
  }

  Future<void> _dialogoTitulo() async {
    final ctrl = TextEditingController(text: widget.pairing.paginaInicial.titulo);
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome no topo da página'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: kMaxTituloHome,
          decoration: const InputDecoration(hintText: 'ex.: Celita'),
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
    if (salvo == true) await widget.pairing.definirTituloDaPagina(ctrl.text);
  }

  Future<void> _dialogoUrl() async {
    final ctrl = TextEditingController(text: widget.pairing.paginaInicial.url);
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Site no lugar da página'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://escola.edu/portal',
            helperText: 'Vazio: a nova aba abre a página do Celita',
          ),
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
    if (salvo != true) return;
    final aceito = await widget.pairing.definirUrlDaPagina(ctrl.text);
    if (!aceito && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Endereço inválido: use http:// ou https://')));
    }
  }

  // O FAB só faz sentido nas abas que têm lista para acrescentar.
  ({IconData icone, String texto, VoidCallback acao})? _fab() => switch (_tabs.index) {
    0 => (icone: Icons.add, texto: 'Novo favorito', acao: _dialogoFavorito),
    1 => (icone: Icons.add, texto: 'Nova regra', acao: _dialogoRegra),
    _ => (icone: Icons.add, texto: 'Novo atalho', acao: _dialogoAtalho),
  };

  @override
  Widget build(BuildContext context) {
    final fab = _fab();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sites'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.star_outline), text: 'Favoritos'),
            Tab(icon: Icon(Icons.shield_outlined), text: 'Regras'),
            Tab(icon: Icon(Icons.home_outlined), text: 'Página inicial'),
          ],
          isScrollable: true,
          tabAlignment: TabAlignment.center,
        ),
      ),
      floatingActionButton: fab == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_sites',
              onPressed: fab.acao,
              icon: Icon(fab.icone),
              label: Text(fab.texto),
            ),
      body: TabBarView(
        controller: _tabs,
        // Sem swipe de página: não briga com o swipe-para-apagar das listas.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          FavoritesView(pairing: widget.pairing, onEditar: (i) => _dialogoFavorito(indice: i)),
          RulesView(pairing: widget.pairing, onEditar: (i) => _dialogoRegra(indice: i)),
          HomePageView(
            pairing: widget.pairing,
            onEditarAtalho: (i) => _dialogoAtalho(indice: i),
            onEditarTitulo: _dialogoTitulo,
            onEditarUrl: _dialogoUrl,
          ),
        ],
      ),
    );
  }
}
