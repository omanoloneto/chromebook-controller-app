// Página inicial dos alunos (View da aba Sites): o que aparece no navegador
// dos computadores da escola. Diferente das outras abas, isto não vai para um
// PC específico — é uma configuração só, publicada para a escola inteira.

import 'package:flutter/material.dart';

import '../pairing/home_store.dart';
import '../pairing/pairing_controller.dart';
import 'theme.dart';

class HomePageView extends StatelessWidget {
  const HomePageView({
    super.key,
    required this.pairing,
    required this.onEditarAtalho,
    required this.onEditarTitulo,
  });

  final PairingController pairing;
  final void Function(int indice) onEditarAtalho;
  final VoidCallback onEditarTitulo;

  @override
  Widget build(BuildContext context) {
    final config = pairing.paginaInicial;
    final erro = pairing.erroPaginaInicial;

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (erro != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cores(context).alertaBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: cores(context).alertaFg),
                const SizedBox(width: 12),
                Expanded(child: Text(erro)),
                TextButton(
                  onPressed: pairing.republicarPaginaInicial,
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),

        const _Titulo('Como a página aparece'),
        ListTile(
          leading: const Icon(Icons.title),
          title: const Text('Nome no topo'),
          subtitle: Text(config.titulo),
          trailing: const Icon(Icons.edit_outlined),
          onTap: onEditarTitulo,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.search),
          title: const Text('Mostrar campo de busca'),
          subtitle: const Text('Desligue se a turma só deve usar os atalhos'),
          value: config.busca,
          onChanged: pairing.definirBuscaDaPagina,
        ),
        if (config.busca)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: kBuscadorGoogle, label: Text('Google')),
                ButtonSegment(value: kBuscadorDuckDuckGo, label: Text('DuckDuckGo')),
              ],
              selected: {config.buscador},
              onSelectionChanged: (sel) => pairing.definirBuscadorDaPagina(sel.first),
            ),
          ),

        _Titulo('Atalhos (${config.atalhos.length} de $kMaxAtalhosHome)'),
        if (config.atalhos.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'Nenhum atalho ainda. Toque em "Novo atalho" aqui embaixo.\n'
              'Eles viram os quadradinhos que os alunos clicam ao abrir o navegador.',
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: config.atalhos.length,
            onReorder: pairing.moverAtalhoDaPagina,
            itemBuilder: (context, i) {
              final atalho = config.atalhos[i];
              return ListTile(
                key: ValueKey('${atalho.url}|$i'),
                leading: const Icon(Icons.apps),
                title: Text(atalho.label),
                subtitle: Text(atalho.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => onEditarAtalho(i),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remover',
                  onPressed: () => pairing.removerAtalhoDaPagina(i),
                ),
              );
            },
          ),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'O que você muda aqui aparece nos computadores da escola quando o '
            'aluno abrir ou recarregar a página inicial.',
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
        letterSpacing: 1.1,
      ),
    ),
  );
}
