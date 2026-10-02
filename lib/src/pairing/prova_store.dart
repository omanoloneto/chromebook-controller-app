// Sites permitidos no modo prova (lista da escola). Arquivo próprio,
// sites_prova.json = {rev, allow:[{pattern}]}, sincronizado em
// school/stores/prova: clientes antigos não conhecem o store e por isso não o
// apagam quando regravam as regras (SPEC-turma §8.5 e §17.4). O "ligado" não
// fica aqui: é da sessão de aula (ClassSessionStore.prova).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../commands/domain_rules.dart';
import '../commands/liberacao.dart';

class ProvaStore {
  ProvaStore._(this._file, this._padroes, this._rev);

  static const fileName = 'sites_prova.json';

  final File _file;
  final List<String> _padroes;
  int _rev;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<ProvaStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$fileName');
    final padroes = <String>[];
    var rev = 0;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          rev = (decoded['rev'] as num?)?.toInt() ?? 0;
          final raw = decoded['allow'];
          if (raw is List) {
            for (final a in raw) {
              final p = a is Map ? a['pattern'] : null;
              if (p is! String) continue;
              final n = normalizarPadrao(p);
              if (n.isNotEmpty && !padroes.contains(n)) padroes.add(n);
              if (padroes.length >= kMaxRules) break;
            }
          }
        }
      } catch (_) {
        // arquivo corrompido -> lista vazia
      }
    }
    return ProvaStore._(file, padroes, rev);
  }

  List<String> get padroes => List.unmodifiable(_padroes);
  int get rev => _rev;

  /// Acrescenta um padrão (normalizado como as regras). false = vazio, largo
  /// demais (sufixo público: liberaria meia internet), repetido ou lista
  /// cheia.
  Future<bool> adicionar(String pattern) async {
    final p = normalizarPadrao(pattern);
    if (!_aceita(p)) return false;
    _padroes.add(p);
    await _save();
    return true;
  }

  /// Vários de uma vez (um por linha, vírgula ou espaço). Devolve quantos
  /// entraram.
  Future<int> adicionarEmLote(String texto) async {
    var n = 0;
    for (final parte in texto.split(RegExp(r'[\s,;]+'))) {
      final p = normalizarPadrao(parte);
      if (!_aceita(p)) continue;
      _padroes.add(p);
      n++;
    }
    if (n > 0) await _save();
    return n;
  }

  bool _aceita(String p) =>
      p.isNotEmpty &&
      !padraoAmploDemais(p) &&
      !_padroes.contains(p) &&
      _padroes.length < kMaxRules;

  Future<void> removerEm(int indice) async {
    if (indice < 0 || indice >= _padroes.length) return;
    _padroes.removeAt(indice);
    await _save();
  }

  Future<void> _save() async {
    _rev = DateTime.now().millisecondsSinceEpoch;
    await _file.writeAsString(
      jsonEncode({
        'rev': _rev,
        'allow': [for (final p in _padroes) {'pattern': p}],
      }),
    );
  }
}
