import 'dart:io';

import 'package:controle_de_aula/src/pairing/wallpaper_store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Directory> _dir() async {
  final dir = await Directory.systemTemp.createTemp('wallpaper_store_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('começa sem papel de parede', () async {
    final store = await WallpaperStore.load(dir: await _dir());
    expect(store.hash, isNull);
  });

  test('o hash sobrevive a reabrir o app', () async {
    final dir = await _dir();
    await (await WallpaperStore.load(dir: dir)).definir('9f2ab41c');
    expect((await WallpaperStore.load(dir: dir)).hash, '9f2ab41c');
  });

  test('arquivo corrompido recomeça sem hash', () async {
    final dir = await _dir();
    await File('${dir.path}/wallpaper.json').writeAsString('{lixo');
    expect((await WallpaperStore.load(dir: dir)).hash, isNull);
  });

  test('hash vazio no arquivo é ignorado', () async {
    final dir = await _dir();
    await File('${dir.path}/wallpaper.json').writeAsString('{"hash": ""}');
    expect((await WallpaperStore.load(dir: dir)).hash, isNull);
  });
}
