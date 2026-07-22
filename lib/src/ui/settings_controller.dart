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
  String? get schoolUid => _prefs.schoolUid;
  bool get onboardingVisto => _prefs.onboardingVisto;

  Future<void> setOnboardingVisto() async {
    await _prefs.setOnboardingVisto();
    // sem notify: flag interna, nada re-renderiza por ela
  }

  Future<void> setTeacherPcId(String? deviceId) async {
    await _prefs.setTeacherPcId(deviceId);
    notifyListeners();
  }

  Future<void> setSchoolUid(String? uid) async {
    await _prefs.setSchoolUid(uid);
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
