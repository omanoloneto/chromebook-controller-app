// Persiste os sites favoritos do professor (ilimitados, com ordem).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Favorito {
  Favorito({required this.label, required this.url});

  final String label;
  final String url;

  Map<String, dynamic> toMap() => {'label': label, 'url': url};

  static Favorito? fromMap(dynamic m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url is! String || url.isEmpty) return null;
    return Favorito(label: m['label'] as String? ?? url, url: url);
  }
}

class FavoritesStore {
  FavoritesStore._(this._file, this._itens);

  static const _fileName = 'favorites.json';

  final File _file;
  final List<Favorito> _itens;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<FavoritesStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var itens = <Favorito>[];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          itens = decoded.map(Favorito.fromMap).whereType<Favorito>().toList();
        }
      } catch (_) {
        // arquivo corrompido -> recomeça vazio
      }
    }
    return FavoritesStore._(file, itens);
  }

  List<Favorito> get itens => List.unmodifiable(_itens);

  Future<void> adicionar(String label, String url) async {
    final l = label.trim();
    final u = url.trim();
    if (u.isEmpty) return;
    _itens.add(Favorito(label: l.isEmpty ? u : l, url: u));
    await _save();
  }

  Future<void> editarEm(int indice, String label, String url) async {
    if (indice < 0 || indice >= _itens.length) return;
    final l = label.trim();
    final u = url.trim();
    if (u.isEmpty) return;
    _itens[indice] = Favorito(label: l.isEmpty ? u : l, url: u);
    await _save();
  }

  Future<void> removerEm(int indice) async {
    if (indice < 0 || indice >= _itens.length) return;
    _itens.removeAt(indice);
    await _save();
  }

  /// Reordena (semântica do ReorderableListView).
  Future<void> mover(int de, int para) async {
    if (de < 0 || de >= _itens.length) return;
    var destino = para;
    if (destino > de) destino -= 1;
    final item = _itens.removeAt(de);
    _itens.insert(destino.clamp(0, _itens.length), item);
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(
      jsonEncode(_itens.map((f) => f.toMap()).toList()),
    );
  }
}
