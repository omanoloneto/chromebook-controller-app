// Lista de regras de sites (View da aba Sites): bloquear ou alertar.
// Criar/editar vem da SitesPage.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../pairing/pairing_controller.dart';
import 'theme.dart';

class RulesView extends StatelessWidget {
  const RulesView({super.key, required this.pairing, required this.onEditar});

  final PairingController pairing;
  final void Function(int indice) onEditar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final regras = pairing.regras;
    return Column(
      children: [
        Expanded(
          child: regras.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 56, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'Bloqueie os sites que atrapalham a aula — vale em '
                          'todos os PCs, até offline.\n\n'
                          'Bloquear: o site não abre no Chromebook.\n'
                          'Alertar: você é avisado quando o aluno entra.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Toque em "Nova regra" aqui embaixo para começar.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: regras.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = regras[i];
                    final bloqueia = r.action == RuleAction.block;
                    return Dismissible(
                      key: ValueKey('${r.pattern}|${r.action}|$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: scheme.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: Icon(Icons.delete, color: scheme.onError),
                      ),
                      onDismissed: (_) => pairing.removerRegra(i),
                      child: ListTile(
                        leading: Icon(
                          bloqueia ? Icons.block : Icons.warning_amber,
                          color: bloqueia ? scheme.error : cores(context).atencao,
                        ),
                        title: Text(r.pattern),
                        subtitle: Text(bloqueia ? 'Bloquear' : 'Alertar'),
                        onTap: () => onEditar(i),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          child: Text(
            'Domínio (youtube.com) vale para subdomínios (m.youtube.com). '
            'Com "/" vira prefixo (reddit.com/r/jogos). '
            'Alterações valem na hora para todos os PCs conectados.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
