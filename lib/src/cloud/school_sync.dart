// Sync dos stores compartilhados do workspace (/school/stores/{k}).
// Modelo: arquivo local inteiro viaja como envelope {json: "<conteúdo>"}
// cifrado com a chave da escola (school_crypto). LWW por arquivo: rev =
// relógio do servidor; aplica remoto só se rev > último visto; push só se o
// conteúdo mudou desde o último sync (hash anti-eco).
//
// A parte de decisão/criptografia é testável sem Firebase
// (prepararPush/aplicarRemoto); só start()/_pushAgora tocam o RTDB.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../secure/crypto.dart';

/// Chave lógica → arquivo local espelhado.
const Map<String, String> kStoresCompartilhados = {
  'turmas': 'turmas.json',
  'rules': 'domain_rules.json',
  'units': 'unit_numbers.json',
  'names': 'device_names.json',
};

class SchoolSync {
  SchoolSync({
    required this.crypto,
    required this.nowServerMs,
    FirebaseDatabase? database,
    Directory? dir,
  })  : _db = database,
        _dir = dir;

  final SessionCrypto crypto;
  final int Function() nowServerMs;
  final FirebaseDatabase? _db; // null em teste (só o núcleo puro)
  final Directory? _dir;

  final Map<String, num> _lastRev = {};
  final Map<String, String> _lastHash = {};
  final Map<String, Timer> _debounce = {};
  final List<StreamSubscription<DatabaseEvent>> _subs = [];

  /// Chamado após aplicar um store remoto (o controller recarrega o store).
  void Function(String k)? onRemoto;

  Future<File> _file(String k) async {
    final base = _dir ?? await getApplicationSupportDirectory();
    return File('${base.path}/${kStoresCompartilhados[k]!}');
  }

  static String _hash(String s) => c.sha256.convert(utf8.encode(s)).toString();

  void start() {
    final db = _db;
    if (db == null) return;
    for (final k in kStoresCompartilhados.keys) {
      _subs.add(
        db.ref('school/stores/$k').onValue.listen((e) {
          final v = e.snapshot.value;
          if (v is Map) {
            aplicarRemoto(k, v['rev'], v['env']).catchError((e) {
              debugPrint('[CdA] sync $k: aplicar falhou: $e');
              return false;
            });
          }
        }),
      );
    }
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
  }

  /// Aplica um snapshot remoto se for mais novo que o último visto.
  /// Retorna true se o arquivo local foi sobrescrito.
  Future<bool> aplicarRemoto(String k, Object? rev, Object? env) async {
    if (rev is! num || env is! String) return false;
    if (rev <= (_lastRev[k] ?? -1)) return false; // já visto/mais velho
    final Map<String, dynamic> msg;
    try {
      msg = await crypto.open(env);
    } catch (_) {
      return false; // envelope de outra chave (escola trocada?) — ignora
    }
    final json = msg['json'];
    if (json is! String) return false;
    _lastRev[k] = rev;
    _lastHash[k] = _hash(json);
    await (await _file(k)).writeAsString(json);
    onRemoto?.call(k);
    return true;
  }

  /// Agenda um push do store (debounce 1 s — rajadas de edição viram 1 write).
  void push(String k) {
    if (_db == null) return;
    _debounce[k]?.cancel();
    _debounce[k] = Timer(const Duration(seconds: 1), () => _pushAgora(k));
  }

  /// Monta o payload do push, ou null se nada mudou desde o último sync.
  Future<Map<String, dynamic>?> prepararPush(String k) async {
    final f = await _file(k);
    if (!await f.exists()) return null;
    final json = await f.readAsString();
    final h = _hash(json);
    if (h == _lastHash[k]) return null; // anti-eco
    final rev = nowServerMs();
    final env = await crypto.seal({'json': json});
    _lastRev[k] = rev;
    _lastHash[k] = h;
    return {'rev': rev, 'env': env};
  }

  Future<void> _pushAgora(String k) async {
    try {
      final payload = await prepararPush(k);
      if (payload == null) return;
      await _db!.ref('school/stores/$k').set(payload);
    } catch (e) {
      debugPrint('[CdA] sync push $k falhou: $e');
    }
  }

  /// Seed do fundador: sobe todos os stores existentes.
  Future<void> pushTodos() async {
    for (final k in kStoresCompartilhados.keys) {
      await _pushAgora(k);
    }
  }
}
