// Número da unidade por PC (deviceId -> 1, 2, 3…), na ordem de pareamento
// DESTE professor. Vai no bind (claro) para a extensão exibir "Unidade N".
// Re-parear o mesmo PC mantém o número; PC esquecido não libera o número
// (a sequência é histórica, não um pool).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UnitStore {
  UnitStore._(this._file, this._numeros);

  static const _fileName = 'unit_numbers.json';

  final File _file;
  final Map<String, int> _numeros;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<UnitStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var numeros = <String, int>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          numeros = decoded.map((k, v) => MapEntry('$k', (v as num).toInt()));
        }
      } catch (_) {
        // arquivo corrompido -> recomeça vazio
      }
    }
    return UnitStore._(file, numeros);
  }

  int? numeroDe(String deviceId) => _numeros[deviceId];

  /// Próximo número livre = maior já atribuído + 1 (começa em 1).
  int proximo() =>
      _numeros.values.fold<int>(0, (max, n) => n > max ? n : max) + 1;

  /// Candidato para um pareamento: reusa o número do device se ele já teve um
  /// (re-pareamento não renumera); senão o próximo da sequência. NÃO persiste
  /// — chame [definir] depois que o bind for aceito, para não queimar número
  /// em pareamento que falhou.
  int candidatoPara(String deviceId) => _numeros[deviceId] ?? proximo();

  Future<void> definir(String deviceId, int numero) async {
    if (_numeros[deviceId] == numero) return;
    _numeros[deviceId] = numero;
    await _file.writeAsString(jsonEncode(_numeros));
  }
}
