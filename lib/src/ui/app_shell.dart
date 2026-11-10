// Shell de navegação: 4 abas fixas (Aula · Turmas · Sites · Ajustes), na barra
// de baixo ou, na janela larga, na lateral.
// IndexedStack preserva o estado de cada aba (ex.: o campo de URL da Aula).

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import '../platform/host.dart';
import 'aula_page.dart';
import 'layout.dart';
import 'settings_controller.dart';
import 'settings_page.dart';
import 'sites_page.dart';
import 'students_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.pairing, required this.settings});

  final PairingController pairing;
  final SettingsController settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Mudar de barra (janela redimensionada, celular girado) não pode zerar as abas.
  final GlobalKey _pagesKey = GlobalKey();

  // "Editar sites" do modo prova: abre a aba Sites já na lista da prova.
  final ValueNotifier<int?> _abaDosSites = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _abaDosSites.dispose();
    super.dispose();
  }

  void _irParaSitesDaProva() {
    _abaDosSites.value = kAbaProva;
    setState(() => _index = 2);
  }

  @override
  void initState() {
    super.initState();
    // Boas-vindas (1x): professor novo entra no workspace com um toque.
    // No computador a conta e a escola já vieram do celular.
    if (!onComputer &&
        !widget.settings.onboardingVisto &&
        !widget.pairing.workspaceAtivo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _boasVindas());
    }
  }

  Future<void> _boasVindas() async {
    if (!mounted) return;
    widget.settings.setOnboardingVisto();
    final entrar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bem-vindo ao Controle de Aula',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Se a sua escola já usa o app, entre com o Google para ver '
                'os PCs, turmas e regras compartilhados pelos professores.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Entrar na escola'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Usar sem conta (sozinho)'),
              ),
            ],
          ),
        ),
      ),
    );
    if (entrar != true || !mounted) return;
    final erro = await widget.pairing.entrarNoWorkspace();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? 'Pronto! Você entrou na escola.'),
      ),
    );
  }

  static const _destinations = [
    (icon: Icons.monitor_outlined, selected: Icons.monitor, label: 'Aula'),
    (icon: Icons.school_outlined, selected: Icons.school, label: 'Turmas'),
    (icon: Icons.language_outlined, selected: Icons.language, label: 'Sites'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Ajustes'),
  ];

  void _select(int index) => setState(() => _index = index);

  // Badge glanceável: PCs online com alerta de site.
  int get _alerts => widget.pairing.pcs
      .where((s) => widget.pairing.isOnline(s) && s.alerta != null)
      .length;

  Widget _icon(IconData icon, int index) {
    if (index != 0) return Icon(icon);
    final alerts = _alerts;
    return Badge.count(
      count: alerts,
      isLabelVisible: alerts > 0,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      key: _pagesKey,
      index: _index,
      children: [
        AulaPage(
          pairing: widget.pairing,
          visivel: _index == 0,
          onIrParaSites: () => _select(2),
          onIrParaSitesDaProva: _irParaSitesDaProva,
          onIrParaTurmas: () => _select(1),
        ),
        StudentsPage(
          pairing: widget.pairing,
          onAulaIniciada: () => _select(0),
        ),
        SitesPage(pairing: widget.pairing, abaPedida: _abaDosSites),
        SettingsPage(pairing: widget.pairing, settings: widget.settings),
      ],
    );
    if (isWideLayout(context)) return _wide(context, pages);
    return Scaffold(
      body: pages,
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.pairing,
        builder: (context, _) => DecoratedBox(
          // Hairline no topo da barra (estilo IG).
          decoration: BoxDecoration(
            border: Border(top: _hairline(context)),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final (i, d) in _destinations.indexed)
                NavigationDestination(
                  icon: _icon(d.icon, i),
                  selectedIcon: _icon(d.selected, i),
                  label: d.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  BorderSide _hairline(BuildContext context) => BorderSide(
        color: hairline(Theme.of(context).brightness),
        width: 0.5,
      );

  Widget _wide(BuildContext context, Widget pages) {
    final media = MediaQuery.of(context);
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: widget.pairing,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                border: Border(right: _hairline(context)),
              ),
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final (i, d) in _destinations.indexed)
                    NavigationRailDestination(
                      icon: _icon(d.icon, i),
                      selectedIcon: _icon(d.selected, i),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              // As páginas centralizam o conteúdo pela largura da janela:
              // aqui a janela delas é o que sobra ao lado da barra.
              builder: (context, box) => MediaQuery(
                data: media
                    .removePadding(removeLeft: true)
                    .copyWith(size: Size(box.maxWidth, media.size.height)),
                child: pages,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
