// Shell de navegação: 4 abas fixas (Aula · Turmas · Sites · Ajustes).
// IndexedStack preserva o estado de cada aba (ex.: o campo de URL da Aula).

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import 'aula_page.dart';
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

  @override
  void initState() {
    super.initState();
    // Boas-vindas (1x): professor novo entra no workspace com um toque.
    if (!widget.settings.onboardingVisto && !widget.pairing.workspaceAtivo) {
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
                child: const Text('Entrar no workspace da escola'),
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
        content: Text(erro ?? 'Você entrou no workspace da escola.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          AulaPage(
            pairing: widget.pairing,
            onIrParaSites: () => setState(() => _index = 2),
          ),
          StudentsPage(pairing: widget.pairing),
          SitesPage(pairing: widget.pairing),
          SettingsPage(pairing: widget.pairing, settings: widget.settings),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.pairing,
        builder: (context, _) {
          // Badge glanceável: PCs online com alerta de site.
          final alertas = widget.pairing.pcs
              .where((s) => widget.pairing.isOnline(s) && s.alerta != null)
              .length;
          return DecoratedBox(
            // Hairline no topo da barra (estilo IG).
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: hairline(Theme.of(context).brightness),
                  width: 0.5,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
              NavigationDestination(
                icon: Badge.count(
                  count: alertas,
                  isLabelVisible: alertas > 0,
                  child: const Icon(Icons.monitor_outlined),
                ),
                selectedIcon: Badge.count(
                  count: alertas,
                  isLabelVisible: alertas > 0,
                  child: const Icon(Icons.monitor),
                ),
                label: 'Aula',
              ),
              const NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: 'Turmas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.language_outlined),
                selectedIcon: Icon(Icons.language),
                label: 'Sites',
              ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Ajustes',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
