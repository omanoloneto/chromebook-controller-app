// Tela de favoritos: sites da aula com 1 toque (ilimitados, reordenáveis).

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

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

  @override
  Widget build(BuildContext context) {
    final itens = widget.pairing.favoritos;
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _dialogoFavorito(),
        icon: const Icon(Icons.add),
        label: const Text('Novo favorito'),
      ),
      body: itens.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum favorito ainda.\n\n'
                  'Cadastre os sites da aula para abrir na turma com 1 toque.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: itens.length,
              onReorder: (de, para) => widget.pairing.moverFavorito(de, para),
              itemBuilder: (_, i) {
                final f = itens[i];
                return ListTile(
                  key: ValueKey('${f.url}|$i'),
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(f.label),
                  subtitle: Text(
                    f.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _dialogoFavorito(indice: i),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remover',
                    onPressed: () => widget.pairing.removerFavorito(i),
                  ),
                );
              },
            ),
    );
  }
}
