// Persiste a sessão de aula em andamento: qual turma está em sala e qual
// aluno está em qual PC (vínculo manual feito pelo professor), mais o que o
// professor ligou para a turma ("Olhos em mim" e modo prova, com as
// liberações de site da prova por PC). Persistida a cada mutação — o app pode
// fechar no meio da aula sem perder o estado (e continua renovando a trava).
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
  // Liberações de bloqueio: deviceId -> padrões. Não dependem de aula; só o
  // "Encerrar aula" as derruba.
  final Map<String, Set<String>> _excecoes = {};

  // "Olhos em mim" ligado por este celular (o rev é o da escrita que ligou).
  TravaDaAula _trava = TravaDaAula.desligada;
  // Modo prova ligado por este celular + hosts liberados na prova, por PC.
  ProvaDaAula _prova = ProvaDaAula.desligada;
  final Map<String, Set<String>> _provaLiberacoes = {};

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
          final e = decoded['excecoes'];
          if (e is Map) {
            e.forEach((k, val) {
              if (k is String && val is List) {
                final padroes = val.whereType<String>().toSet();
                if (padroes.isNotEmpty) store._excecoes[k] = padroes;
              }
            });
          }
          store._trava = TravaDaAula.fromMap(decoded['trava']);
          store._prova = ProvaDaAula.fromMap(decoded['prova']);
          final pl = decoded['provaLiberacoes'];
          if (pl is Map) {
            pl.forEach((k, val) {
              if (k is String && val is List) {
                final hosts = val.whereType<String>().toSet();
                if (hosts.isNotEmpty) store._provaLiberacoes[k] = hosts;
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

  /// Padrões de bloqueio liberados para um PC.
  Set<String> excecoesDe(String deviceId) =>
      Set.unmodifiable(_excecoes[deviceId] ?? const {});

  /// PCs com alguma liberação ativa.
  List<String> get devicesComExcecao => _excecoes.keys.toList();

  TravaDaAula get trava => _trava;
  ProvaDaAula get prova => _prova;

  /// Hosts liberados na prova para um PC (somam à lista da escola).
  Set<String> provaLiberacoesDe(String deviceId) =>
      Set.unmodifiable(_provaLiberacoes[deviceId] ?? const {});

  Future<void> definirTrava(TravaDaAula trava) async {
    _trava = trava;
    await _save();
  }

  Future<void> definirProva(ProvaDaAula prova) async {
    _prova = prova;
    await _save();
  }

  /// Libera um host na prova para um PC (pedido aprovado em prova). true =
  /// o host entrou agora (não estava liberado).
  Future<bool> liberarNaProva(String deviceId, String host) async {
    final novo = (_provaLiberacoes[deviceId] ??= {}).add(host);
    if (novo) await _save();
    return novo;
  }

  /// Desfaz [liberarNaProva] (a gravação do state/exam falhou: a liberação
  /// não pode entrar escondida na próxima renovação da prova).
  Future<void> revogarNaProva(String deviceId, String host) async {
    final hosts = _provaLiberacoes[deviceId];
    if (hosts == null || !hosts.remove(host)) return;
    if (hosts.isEmpty) _provaLiberacoes.remove(deviceId);
    await _save();
  }

  Future<void> iniciar(String turma) async {
    _ativa = true;
    _turma = turma;
    _inicio = DateTime.now().millisecondsSinceEpoch;
    _vinculos.clear();
    await _save();
  }

  /// Libera um padrão de bloqueio para um PC (com ou sem aula).
  Future<void> liberar(String deviceId, String pattern) async {
    (_excecoes[deviceId] ??= {}).add(pattern);
    await _save();
  }

  /// Revoga a liberação (o bloqueio volta a valer).
  Future<void> revogar(String deviceId, String pattern) async {
    final s = _excecoes[deviceId];
    if (s == null || !s.remove(pattern)) return;
    if (s.isEmpty) _excecoes.remove(deviceId);
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
    _excecoes.clear();
    _trava = TravaDaAula.desligada;
    _prova = ProvaDaAula.desligada;
    _provaLiberacoes.clear();
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(
      jsonEncode({
        'ativa': _ativa,
        'turma': _turma,
        'inicio': _inicio,
        'vinculos': _vinculos,
        'excecoes': _excecoes.map((k, v) => MapEntry(k, v.toList())),
        'trava': _trava.toMap(),
        'prova': _prova.toMap(),
        'provaLiberacoes':
            _provaLiberacoes.map((k, v) => MapEntry(k, v.toList())),
      }),
    );
  }
}

/// "Olhos em mim" da aula: ligado, rev da escrita que ligou, texto, mute e
/// desde quando (para a faixa "desde 10:42").
class TravaDaAula {
  const TravaDaAula({
    required this.on,
    this.rev = 0,
    this.texto = '',
    this.mute = true,
    this.desde = 0,
  });

  static const desligada = TravaDaAula(on: false);

  final bool on;
  final int rev;
  final String texto;
  final bool mute;
  final int desde; // ms

  Map<String, dynamic> toMap() =>
      {'on': on, 'rev': rev, 'texto': texto, 'mute': mute, 'desde': desde};

  static TravaDaAula fromMap(dynamic m) {
    if (m is! Map || m['on'] != true) return desligada;
    return TravaDaAula(
      on: true,
      rev: (m['rev'] as num?)?.toInt() ?? 0,
      texto: m['texto'] as String? ?? '',
      mute: m['mute'] != false,
      desde: (m['desde'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Modo prova da aula: ligado e rev da escrita que ligou.
class ProvaDaAula {
  const ProvaDaAula({required this.on, this.rev = 0});

  static const desligada = ProvaDaAula(on: false);

  final bool on;
  final int rev;

  Map<String, dynamic> toMap() => {'on': on, 'rev': rev};

  static ProvaDaAula fromMap(dynamic m) {
    if (m is! Map || m['on'] != true) return desligada;
    return ProvaDaAula(on: true, rev: (m['rev'] as num?)?.toInt() ?? 0);
  }
}
