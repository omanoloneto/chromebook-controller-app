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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum favorito ainda.\n\n'
            'Cadastre os sites da aula para abrir na turma com 1 toque.',
            textAlign: TextAlign.center,
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
