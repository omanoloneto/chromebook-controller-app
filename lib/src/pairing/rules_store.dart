// Persiste as regras de domínio do professor (bloqueio/alerta).
// `rev` = epoch-ms da última edição — viaja no set_rules para idempotência.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../commands/domain_rules.dart';
import '../commands/filtros.dart';

class RulesStore {
  RulesStore._(this._file, this._rules, this._rev, this._filtros);

  static const _fileName = 'domain_rules.json';

  final File _file;
  final List<DomainRule> _rules;
  int _rev;

  // Os filtros viajam no mesmo arquivo das regras: a escola já sincroniza
  // este arquivo inteiro, então não precisam de nó novo no Firebase.
  Filtros _filtros;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<RulesStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var rules = <DomainRule>[];
    var rev = 0;
    var filtros = Filtros.padrao;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          rev = (decoded['rev'] as num?)?.toInt() ?? 0;
          final raw = decoded['rules'];
          if (raw is List) {
            rules = raw.map(DomainRule.fromMap).whereType<DomainRule>().toList();
          }
          filtros = Filtros.fromMap(decoded['filtros']);
        }
      } catch (_) {
        // arquivo corrompido -> recomeça vazio
      }
    }
    return RulesStore._(file, rules, rev, filtros);
  }

  List<DomainRule> get regras => List.unmodifiable(_rules);
  int get rev => _rev;
  Filtros get filtros => _filtros;

  Future<void> definirFiltros(Filtros filtros) async {
    _filtros = filtros;
    await _save();
  }

  Future<void> adicionar(String pattern, String action) async {
    final p = normalizarPadrao(pattern);
    if (p.isEmpty) return;
    _rules.removeWhere((r) => r.pattern == p); // sem duplicatas
    _rules.add(DomainRule(pattern: p, action: action));
    await _save();
  }

  Future<void> atualizarEm(int indice, String pattern, String action) async {
    if (indice < 0 || indice >= _rules.length) return;
    final p = normalizarPadrao(pattern);
    if (p.isEmpty) return;
    _rules[indice] = DomainRule(pattern: p, action: action);
    await _save();
  }

  Future<void> removerEm(int indice) async {
    if (indice < 0 || indice >= _rules.length) return;
    _rules.removeAt(indice);
    await _save();
  }

  Future<void> _save() async {
    _rev = DateTime.now().millisecondsSinceEpoch;
    await _file.writeAsString(
      jsonEncode({
        'rev': _rev,
        'rules': _rules.map((r) => r.toMap()).toList(),
        'filtros': _filtros.toMap(),
      }),
    );
  }
}
