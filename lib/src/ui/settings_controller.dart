// Wrapper observável sobre o PrefsStore: o root escuta p/ trocar o themeMode
// do MaterialApp na hora; Ajustes escuta p/ refletir o estado.

import 'package:flutter/material.dart';

import '../pairing/prefs_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  final PrefsStore _prefs;

  ThemeMode get themeMode => _prefs.themeMode;
  String get nomeProfessor => _prefs.teacherName;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setNomeProfessor(String nome) async {
    await _prefs.setTeacherName(nome);
    notifyListeners();
  }
}
