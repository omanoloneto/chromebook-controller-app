// Regras de sites (View da aba Sites): filtros prontos (vídeos curtos, canais
// e IAs) e a lista de sites para bloquear ou só avisar. Criar/editar regra vem
// da SitesPage.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../commands/filtros.dart';
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
    final f = pairing.filtros;
    void mudar(Filtros novos) => pairing.definirFiltros(novos);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        const _Titulo('Vídeos curtos e IAs'),
        SwitchListTile(
          secondary: const Icon(Icons.smart_display_outlined),
          title: const Text('Esconder os Shorts do YouTube'),
          subtitle: const Text('O YouTube continua liberado para pesquisa.'),
          value: f.shorts,
          onChanged: (v) => mudar(f.copyWith(shorts: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.movie_filter_outlined),
          title: const Text('Esconder os Reels do Instagram'),
          value: f.reels,
          onChanged: (v) => mudar(f.copyWith(reels: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.music_video_outlined),
          title: const Text('Bloquear o TikTok'),
          value: f.tiktok,
          onChanged: (v) => mudar(f.copyWith(tiktok: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Bloquear IAs'),
          subtitle: const Text(
            'Gemini, ChatGPT, Copilot e outras, e o resumo de IA da pesquisa do '
            'Google. Dá para liberar num PC até o aluno sair da conta.',
          ),
          value: f.ias,
          onChanged: (v) => mudar(f.copyWith(ias: v)),
        ),
        ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('Canais do YouTube bloqueados'),
          subtitle: Text(
            f.canais.isEmpty
                ? 'Nenhum'
                : f.canais.length == 1
                    ? '1 canal'
                    : '${f.canais.length} canais',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => mostrarSheetCanais(context, pairing),
        ),
        const Divider(height: 1),
        const _Titulo('Sites'),
        if (regras.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Bloqueie os sites que atrapalham a aula — vale em todos os PCs, '
              'até offline.\n\n'
              'Bloquear (e me avisar): o site não abre e você é avisado da '
              'tentativa.\n'
              'Só me avisar: o site abre e você é avisado.\n\n'
              'Toque em "Nova regra" aqui embaixo para começar.',
            ),
          ),
        for (var i = 0; i < regras.length; i++) ...[
          Dismissible(
            key: ValueKey('${regras[i].pattern}|${regras[i].action}|$i'),
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
                regras[i].action == RuleAction.block ? Icons.block : Icons.warning_amber,
                color: regras[i].action == RuleAction.block ? scheme.error : cores(context).atencao,
              ),
              title: Text(regras[i].pattern),
              subtitle: Text(
                regras[i].action == RuleAction.block ? 'Bloquear (e me avisar)' : 'Só me avisar',
              ),
              onTap: () => onEditar(i),
            ),
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Domínio (youtube.com) vale para subdomínios (m.youtube.com). '
            'Com "/" vira prefixo (reddit.com/r/jogos). '
            'Alterações valem na hora para todos os PCs conectados.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// Sheet para bloquear e desbloquear canais do YouTube.
Future<void> mostrarSheetCanais(BuildContext context, PairingController pairing) {
  final ctrl = TextEditingController();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final canais = pairing.filtros.canais;
        Future<void> adicionar() async {
          final canal = normalizarCanal(ctrl.text);
          if (canal == null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('Não reconheci o canal. Cole o link do canal ou escreva o @nome.')),
              );
            return;
          }
          if (!canais.contains(canal)) {
            await pairing.definirFiltros(pairing.filtros.copyWith(canais: [...canais, canal]));
          }
          ctrl.clear();
          setSheet(() {});
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('Canais do YouTube bloqueados'),
                  subtitle: Text(
                    'O canal, os vídeos dele e ele nas buscas e sugestões '
                    'somem nos PCs dos alunos.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      labelText: 'Link do canal ou @nome',
                      hintText: 'youtube.com/@canal',
                      suffixIcon: IconButton(
                        tooltip: 'Bloquear canal',
                        icon: const Icon(Icons.add),
                        onPressed: adicionar,
                      ),
                    ),
                    onSubmitted: (_) => adicionar(),
                  ),
                ),
                const SizedBox(height: 8),
                if (canais.isEmpty)
                  const ListTile(title: Text('Nenhum canal bloqueado.')),
                for (final canal in canais)
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: Text(canal),
                    trailing: IconButton(
                      tooltip: 'Desbloquear canal',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await pairing.definirFiltros(
                          pairing.filtros.copyWith(canais: [...canais]..remove(canal)),
                        );
                        setSheet(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
