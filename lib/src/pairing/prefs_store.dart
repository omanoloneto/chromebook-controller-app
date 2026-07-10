// Preferências do app (tema e nome do professor) — JSON local, padrão dos
// demais stores.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class PrefsStore {
  PrefsStore._(this._file);

  static const _fileName = 'app_prefs.json';

  final File _file;

  ThemeMode _themeMode = ThemeMode.system;
  String _teacherName = 'Professor';
  bool _notificarSites = true;
  String? _teacherPcId; // deviceId do "PC do professor" (null = nenhum)

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<PrefsStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final store = PrefsStore._(File('${base.path}/$_fileName'));
    if (await store._file.exists()) {
      try {
        final decoded = jsonDecode(await store._file.readAsString());
        if (decoded is Map) {
          store._themeMode = switch (decoded['themeMode']) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          final nome = decoded['teacherName'];
          if (nome is String && nome.trim().isNotEmpty) {
            store._teacherName = nome.trim();
          }
          if (decoded['notificarSites'] is bool) {
            store._notificarSites = decoded['notificarSites'] as bool;
          }
          final pcProf = decoded['teacherPcId'];
          if (pcProf is String && pcProf.isNotEmpty) {
            store._teacherPcId = pcProf;
          }
        }
      } catch (_) {
        // arquivo corrompido -> defaults
      }
    }
    return store;
  }

  ThemeMode get themeMode => _themeMode;
  String get teacherName => _teacherName;
  bool get notificarSites => _notificarSites;
  String? get teacherPcId => _teacherPcId;

  Future<void> setNotificarSites(bool valor) async {
    _notificarSites = valor;
    await _save();
  }

  Future<void> setTeacherPcId(String? deviceId) async {
    _teacherPcId = (deviceId != null && deviceId.isEmpty) ? null : deviceId;
    await _save();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _save();
  }

  Future<void> setTeacherName(String nome) async {
    final n = nome.trim();
    _teacherName = n.isEmpty ? 'Professor' : n;
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(
      jsonEncode({
        'themeMode': switch (_themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
        'teacherName': _teacherName,
        'notificarSites': _notificarSites,
        if (_teacherPcId != null) 'teacherPcId': _teacherPcId,
      }),
    );
  }
}
