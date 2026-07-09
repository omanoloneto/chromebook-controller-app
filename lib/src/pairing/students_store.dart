// Persiste as turmas do professor e seus alunos (só no celular — os nomes
// dos alunos NUNCA vão para o Firebase nem para os Chromebooks).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Turma {
  Turma({required this.nome, List<String>? alunos}) : alunos = alunos ?? [];

  String nome;
  final List<String> alunos;

  Map<String, dynamic> toMap() => {'nome': nome, 'alunos': alunos};

  static Turma? fromMap(dynamic m) {
    if (m is! Map) return null;
    final nome = m['nome'];
    if (nome is! String || nome.isEmpty) return null;
    final alunos = <String>[];
    final raw = m['alunos'];
    if (raw is List) {
      for (final a in raw) {
        if (a is String && a.isNotEmpty) alunos.add(a);
      }
    }
    return Turma(nome: nome, alunos: alunos);
  }
}

class StudentsStore {
  StudentsStore._(this._file, this._turmas);

  static const _fileName = 'turmas.json';

  final File _file;
  final List<Turma> _turmas;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<StudentsStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var turmas = <Turma>[];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          turmas = decoded.map(Turma.fromMap).whereType<Turma>().toList();
        }
      } catch (_) {
        // arquivo corrompido -> recomeça vazio
      }
    }
    return StudentsStore._(file, turmas);
  }

  List<Turma> get turmas => List.unmodifiable(_turmas);

  Turma? turmaPorNome(String nome) {
    for (final t in _turmas) {
      if (t.nome == nome) return t;
    }
    return null;
  }

  // ---- Turmas -----------------------------------------------------------------

  Future<void> adicionarTurma(String nome) async {
    final n = nome.trim();
    if (n.isEmpty || turmaPorNome(n) != null) return;
    _turmas.add(Turma(nome: n));
    await _save();
  }

  Future<void> renomearTurma(int indice, String nome) async {
    final n = nome.trim();
    if (indice < 0 || indice >= _turmas.length || n.isEmpty) return;
    if (turmaPorNome(n) != null && _turmas[indice].nome != n) return;
    _turmas[indice].nome = n;
    await _save();
  }

  Future<void> removerTurma(int indice) async {
    if (indice < 0 || indice >= _turmas.length) return;
    _turmas.removeAt(indice);
    await _save();
  }

  // ---- Alunos -----------------------------------------------------------------

  Future<void> adicionarAluno(int turmaIndice, String aluno) async {
    if (turmaIndice < 0 || turmaIndice >= _turmas.length) return;
    final a = aluno.trim();
    final t = _turmas[turmaIndice];
    if (a.isEmpty || t.alunos.contains(a)) return;
    t.alunos.add(a);
    await _save();
  }

  Future<void> renomearAluno(int turmaIndice, int alunoIndice, String nome) async {
    if (turmaIndice < 0 || turmaIndice >= _turmas.length) return;
    final t = _turmas[turmaIndice];
    final n = nome.trim();
    if (alunoIndice < 0 || alunoIndice >= t.alunos.length || n.isEmpty) return;
    if (t.alunos.contains(n) && t.alunos[alunoIndice] != n) return;
    t.alunos[alunoIndice] = n;
    await _save();
  }

  Future<void> removerAluno(int turmaIndice, int alunoIndice) async {
    if (turmaIndice < 0 || turmaIndice >= _turmas.length) return;
    final t = _turmas[turmaIndice];
    if (alunoIndice < 0 || alunoIndice >= t.alunos.length) return;
    t.alunos.removeAt(alunoIndice);
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(
      jsonEncode(_turmas.map((t) => t.toMap()).toList()),
    );
  }
}
