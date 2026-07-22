// Lista de favoritos (View da aba Sites): reordenável, swipe não — o
// arrastar já é o gesto de reordenar. Criar/editar vem da SitesPage.

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import 'theme.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key, required this.pairing, required this.onEditar});

  final PairingController pairing;
  final void Function(int indice) onEditar;

  @override
  Widget build(BuildContext context) {
    final itens = pairing.favoritos;
    if (itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.star_outline,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              const Text(
                'Salve aqui os sites que você mais usa na aula.\n'
                'Eles viram botões na tela Aula — a turma toda abre com 1 toque.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Toque em "Novo favorito" aqui embaixo para começar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: itens.length,
      onReorder: (de, para) => pairing.moverFavorito(de, para),
      itemBuilder: (context, i) {
        final f = itens[i];
        return ListTile(
          key: ValueKey('${f.url}|$i'),
          leading: Icon(Icons.star, color: cores(context).favorito),
          title: Text(f.label),
          subtitle: Text(f.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onEditar(i),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover',
            onPressed: () => pairing.removerFavorito(i),
          ),
        );
      },
    );
  }
}
