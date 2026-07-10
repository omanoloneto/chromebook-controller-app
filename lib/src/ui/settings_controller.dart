// Wrapper observável sobre o PrefsStore: o root escuta p/ trocar o themeMode
// do MaterialApp na hora; Ajustes escuta p/ refletir o estado.

import 'package:flutter/material.dart';

import '../pairing/prefs_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  final PrefsStore _prefs;

  ThemeMode get themeMode => _prefs.themeMode;
  String get nomeProfessor => _prefs.teacherName;
  bool get notificarSites => _prefs.notificarSites;
  String? get teacherPcId => _prefs.teacherPcId;

  Future<void> setTeacherPcId(String? deviceId) async {
    await _prefs.setTeacherPcId(deviceId);
    notifyListeners();
  }

  Future<void> setNotificarSites(bool valor) async {
    await _prefs.setNotificarSites(valor);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setNomeProfessor(String nome) async {
    await _prefs.setTeacherName(nome);
    notifyListeners();
  }
}
