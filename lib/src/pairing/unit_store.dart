// Número da unidade por PC (deviceId -> 1, 2, 3…) DESTE professor. Vai no
// bind (claro) para a extensão exibir "Unidade N". Pareamento novo recebe o
// MENOR número livre — buracos (criados por edição manual, ex.: mudar um PC
// p/ 98 libera o antigo) são reaproveitados. Re-parear o mesmo PC mantém o
// número; PC esquecido continua dono do dele (volta com o mesmo se re-parear).

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

  /// Quem é o dono de um número (lookup reverso, p/ o swap na edição).
  String? deviceIdDoNumero(int numero) {
    for (final e in _numeros.entries) {
      if (e.value == numero) return e.key;
    }
    return null;
  }

  /// Menor número livre (1..): com 1..22 e 98 ocupados, o próximo é 23.
  int proximo() {
    final usados = _numeros.values.toSet();
    var n = 1;
    while (usados.contains(n)) {
      n++;
    }
    return n;
  }

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
