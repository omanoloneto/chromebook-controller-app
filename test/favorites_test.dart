// FavoritesStore: round-trip, edição e reordenação.

import 'dart:io';

import 'package:controle_de_aula/src/pairing/favorites_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trip: adiciona, edita, reordena, remove', () async {
    final dir = await Directory.systemTemp.createTemp('fav_test');
    try {
      final store = await FavoritesStore.load(dir: dir);
      await store.adicionar('Khan', 'https://pt.khanacademy.org');
      await store.adicionar('', 'https://wikipedia.org'); // label vazio -> URL
      await store.adicionar('Escola', 'https://escola.example');
      expect(store.itens, hasLength(3));
      expect(store.itens[1].label, 'https://wikipedia.org');

      await store.mover(2, 0); // 'Escola' para o topo
      final relido = await FavoritesStore.load(dir: dir);
      expect(relido.itens.first.label, 'Escola');

      await relido.editarEm(0, 'Portal', 'https://portal.example');
      await relido.removerEm(2);
      final fin = await FavoritesStore.load(dir: dir);
      expect(fin.itens, hasLength(2));
      expect(fin.itens.first.label, 'Portal');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
