// Aba Sites: Favoritos, Regras, a Página inicial dos alunos e os sites
// permitidos no modo prova (tabs). FAB contextual.
// As Views são burras; os dialogs de criar/editar vivem aqui.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../pairing/pairing_controller.dart';
import '../pairing/home_store.dart';
import 'favorites_page.dart';
import 'home_page_view.dart';
import 'prova_controles.dart';
import 'rules_page.dart';

/// Abas da tela Sites (o "Editar sites" do modo prova pede a [kAbaProva]).
const int kAbaProva = 3;

class SitesPage extends StatefulWidget {
  const SitesPage({super.key, required this.pairing, this.abaPedida});

  final PairingController pairing;

  /// Outra tela pede uma aba (ex.: [kAbaProva] pelo "Editar sites").
  final ValueNotifier<int?>? abaPedida;

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
    _tabs.addListener(_onChange); // troca o FAB junto com a aba
    widget.abaPedida?.addListener(_irParaAbaPedida);
    _irParaAbaPedida();
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    widget.abaPedida?.removeListener(_irParaAbaPedida);
    _tabs.dispose();
    super.dispose();
  }

  void _irParaAbaPedida() {
    final pedida = widget.abaPedida;
    final aba = pedida?.value;
    if (pedida == null || aba == null || aba < 0 || aba >= _tabs.length) return;
    _tabs.animateTo(aba);
    pedida.value = null;
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
              // Vertical: os nomes longos não cabem lado a lado no diálogo.
              SegmentedButton<String>(
                direction: Axis.vertical,
                segments: const [
                  ButtonSegment(
                    value: RuleAction.block,
                    label: Text('Bloquear (e me avisar)'),
                    icon: Icon(Icons.block),
                  ),
                  ButtonSegment(
                    value: RuleAction.alert,
                    label: Text('Só me avisar'),
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
        title: const Text('Site que abre com o navegador'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://escola.edu/portal',
            helperText: 'Abre quando o aluno abre o navegador e no botão '
                'Início (casinha). A nova aba continua mostrando a página do '
                'Celita.',
            helperMaxLines: 4,
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
    kAbaProva => (
        icone: Icons.add,
        texto: 'Novo site',
        acao: () => dialogoNovoSiteProva(context, widget.pairing),
      ),
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
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Prova'),
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
          ProvaSitesView(pairing: widget.pairing),
        ],
      ),
    );
  }
}
