// Persiste a sessão de aula em andamento: qual turma está em sala e qual
// aluno está em qual PC (vínculo manual feito pelo professor). Persistida a
// cada mutação — o app pode fechar no meio da aula sem perder o estado.
// Só no celular; nada disso vai para o Firebase.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ClassSessionStore {
  ClassSessionStore._(this._file);

  static const _fileName = 'aula.json';

  final File _file;

  bool _ativa = false;
  String _turma = '';
  int _inicio = 0;
  final Map<String, String> _vinculos = {}; // deviceId -> aluno

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<ClassSessionStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final store = ClassSessionStore._(File('${base.path}/$_fileName'));
    if (await store._file.exists()) {
      try {
        final decoded = jsonDecode(await store._file.readAsString());
        if (decoded is Map) {
          store._ativa = decoded['ativa'] == true;
          store._turma = decoded['turma'] as String? ?? '';
          store._inicio = (decoded['inicio'] as num?)?.toInt() ?? 0;
          final v = decoded['vinculos'];
          if (v is Map) {
            v.forEach((k, val) {
              if (k is String && val is String && val.isNotEmpty) {
                store._vinculos[k] = val;
              }
            });
          }
        }
      } catch (_) {
        // arquivo corrompido -> sem aula ativa
      }
    }
    return store;
  }

  bool get ativa => _ativa;
  String get turma => _turma;
  DateTime get inicio => DateTime.fromMillisecondsSinceEpoch(_inicio);
  Map<String, String> get vinculos => Map.unmodifiable(_vinculos);

  String? alunoDe(String deviceId) => _vinculos[deviceId];

  Future<void> iniciar(String turma) async {
    _ativa = true;
    _turma = turma;
    _inicio = DateTime.now().millisecondsSinceEpoch;
    _vinculos.clear();
    await _save();
  }

  Future<void> vincular(String deviceId, String aluno) async {
    if (!_ativa) return;
    // Um aluno só pode estar em um PC por vez.
    _vinculos.removeWhere((_, a) => a == aluno);
    _vinculos[deviceId] = aluno;
    await _save();
  }

  Future<void> desvincular(String deviceId) async {
    if (_vinculos.remove(deviceId) != null) await _save();
  }

  Future<void> encerrar() async {
    _ativa = false;
    _turma = '';
    _inicio = 0;
    _vinculos.clear();
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(
      jsonEncode({
        'ativa': _ativa,
        'turma': _turma,
        'inicio': _inicio,
        'vinculos': _vinculos,
      }),
    );
  }
}
