// Testes das preferências do app (tema + nome do professor).

import 'dart:io';

import 'package:controle_de_aula/src/pairing/prefs_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cda_prefs_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('defaults: sistema + "Professor"', () async {
    final p = await PrefsStore.load(dir: tmp);
    expect(p.themeMode, ThemeMode.system);
    expect(p.teacherName, 'Professor');
  });

  test('persiste tema e nome entre loads', () async {
    var p = await PrefsStore.load(dir: tmp);
    await p.setThemeMode(ThemeMode.dark);
    await p.setTeacherName('  Prof. Mano  ');

    p = await PrefsStore.load(dir: tmp);
    expect(p.themeMode, ThemeMode.dark);
    expect(p.teacherName, 'Prof. Mano'); // trim aplicado
  });

  test('nome vazio volta ao default', () async {
    final p = await PrefsStore.load(dir: tmp);
    await p.setTeacherName('   ');
    expect(p.teacherName, 'Professor');
  });

  test('arquivo corrompido recomeça com defaults', () async {
    await File('${tmp.path}/app_prefs.json').writeAsString('{quebrado');
    final p = await PrefsStore.load(dir: tmp);
    expect(p.themeMode, ThemeMode.system);
    expect(p.teacherName, 'Professor');
  });
}
