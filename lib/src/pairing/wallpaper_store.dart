// Hash do papel de parede vigente. Sem persistir, reabrir o app perdia o hash
// e um PC pareado depois nunca recebia a imagem já publicada.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class WallpaperStore {
  WallpaperStore._(this._file, this._hash);

  static const _fileName = 'wallpaper.json';

  final File _file;
  String? _hash;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<WallpaperStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    String? hash;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        final valor = decoded is Map ? decoded['hash'] : null;
        if (valor is String && valor.isNotEmpty) hash = valor;
      } catch (_) {
        // arquivo corrompido -> sem papel de parede vigente
      }
    }
    return WallpaperStore._(file, hash);
  }

  String? get hash => _hash;

  Future<void> definir(String hash) async {
    _hash = hash;
    await _file.writeAsString(jsonEncode({'hash': hash}));
  }
}
