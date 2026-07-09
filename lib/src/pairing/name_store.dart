// Persiste os nomes que o professor dá aos PCs (deviceId -> nome do aluno).
// Metadado só do celular: sobrevive a reinícios; nada é enviado ao Chromebook.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class NameStore {
  NameStore._(this._file, this._names);

  static const _fileName = 'device_names.json';

  final File _file;
  final Map<String, String> _names;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<NameStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var names = <String, String>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          names = decoded.map((k, v) => MapEntry('$k', '$v'));
        }
      } catch (_) {
        // arquivo corrompido -> recomeça vazio
      }
    }
    return NameStore._(file, names);
  }

  String? nameOf(String deviceId) => _names[deviceId];

  /// Nome vazio remove o apelido (volta ao label padrão).
  Future<void> setName(String deviceId, String name) async {
    final limpo = name.trim();
    if (limpo.isEmpty) {
      _names.remove(deviceId);
    } else {
      _names[deviceId] = limpo;
    }
    await _file.writeAsString(jsonEncode(_names));
  }
}
