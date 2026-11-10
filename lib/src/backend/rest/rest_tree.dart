// Árvore de dados do banco em memória e as regras do Realtime Database que o
// SDK aplicaria: ordem das chaves, mapa denso que vira lista, nó vazio = null.

import 'dart:math';

import '../realtime_db.dart';

final RegExp _integerKey = RegExp(r'^(0|-?[1-9]\d*)$');
final RegExp _indexKey = RegExp(r'^(0|[1-9]\d*)$');

List<String> splitPath(String? path) => [
      for (final segment in (path ?? '').split('/'))
        if (segment.isNotEmpty) segment,
    ];

int? _asInt32(String key) {
  if (key.length > 11 || !_integerKey.hasMatch(key)) return null;
  final value = int.parse(key);
  return value >= -2147483648 && value <= 2147483647 ? value : null;
}

/// Ordem por chave do banco: inteiros de 32 bits primeiro, em ordem
/// numérica; depois o resto, em ordem de texto.
int compareKeys(String a, String b) {
  final x = _asInt32(a);
  final y = _asInt32(b);
  if (x != null) return y == null ? -1 : x.compareTo(y);
  return y != null ? 1 : a.compareTo(b);
}

/// JSON do servidor na forma interna: só mapas de texto e folhas.
Object? normalize(Object? json) {
  final Iterable<MapEntry<String, Object?>> entries;
  if (json is List) {
    entries = [
      for (var i = 0; i < json.length; i++) MapEntry('$i', json[i]),
    ];
  } else if (json is Map) {
    entries = json.entries.map((e) => MapEntry('${e.key}', e.value));
  } else {
    return json;
  }
  final node = <String, Object?>{};
  for (final entry in entries) {
    final child = normalize(entry.value);
    if (child != null) node[entry.key] = child;
  }
  return node.isEmpty ? null : node;
}

Object? valueAt(Object? tree, List<String> path) {
  var node = tree;
  for (final key in path) {
    if (node is! Map<String, Object?>) return null;
    node = node[key];
  }
  return node;
}

/// Árvore nova com [value] (já normalizado) em [path]. O que não mudou
/// continua sendo o mesmo objeto: é o que deixa barato saber quem avisar.
Object? withValueAt(
  Object? tree,
  List<String> path,
  Object? value, [
  int depth = 0,
]) {
  if (depth == path.length) return value;
  final key = path[depth];
  final node = tree is Map<String, Object?> ? tree : const <String, Object?>{};
  final before = node[key];
  final child = withValueAt(before, path, value, depth + 1);
  if (identical(child, before)) return tree;
  final next = Map<String, Object?>.of(node);
  if (child == null) {
    next.remove(key);
  } else {
    next[key] = child;
  }
  return next.isEmpty ? null : next;
}

bool sameTree(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!sameTree(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Valor como o SDK entrega: chaves em ordem e lista quando o mapa é denso.
Object? export(Object? tree) {
  if (tree is! Map<String, Object?>) return tree;
  final keys = tree.keys.toList()..sort(compareKeys);
  var maxIndex = -1;
  var onlyIndexes = true;
  for (final key in keys) {
    if (key.length <= 10 && _indexKey.hasMatch(key)) {
      maxIndex = max(maxIndex, int.parse(key));
    } else {
      onlyIndexes = false;
      break;
    }
  }
  if (onlyIndexes && maxIndex < 2 * keys.length) {
    return [for (var i = 0; i <= maxIndex; i++) export(tree['$i'])];
  }
  return <String, Object?>{for (final key in keys) key: export(tree[key])};
}

final class RestSnapshot implements DbSnapshot {
  const RestSnapshot(this.key, this.value);

  /// A partir do JSON de uma resposta.
  RestSnapshot.fromJson(String? key, Object? json)
      : this(key, export(normalize(json)));

  @override
  final String? key;

  @override
  final Object? value;

  @override
  bool get exists => value != null;

  @override
  Iterable<DbSnapshot> get children {
    final node = value;
    if (node is Map<String, Object?>) {
      return node.entries.map((e) => RestSnapshot(e.key, e.value));
    }
    if (node is List<Object?>) {
      return [
        for (var i = 0; i < node.length; i++)
          if (node[i] != null) RestSnapshot('$i', node[i]),
      ];
    }
    return const [];
  }
}

/// Chaves de push geradas no cliente, como o SDK: ordenam por hora e não
/// repetem dentro do mesmo milissegundo.
final class PushIds {
  PushIds([Random? random]) : _random = random ?? Random.secure();

  static const String _alphabet =
      '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

  final Random _random;
  final List<int> _tail = List.filled(12, 0);
  int _lastMs = -1;

  String next(int nowMs) {
    final sameMs = nowMs == _lastMs;
    _lastMs = nowMs;
    final head = List.filled(8, '');
    var rest = nowMs;
    for (var i = 7; i >= 0; i--) {
      head[i] = _alphabet[rest % 64];
      rest ~/= 64;
    }
    if (sameMs) {
      var i = 11;
      while (i >= 0 && _tail[i] == 63) {
        _tail[i--] = 0;
      }
      if (i >= 0) _tail[i]++;
    } else {
      for (var i = 0; i < 12; i++) {
        _tail[i] = _random.nextInt(64);
      }
    }
    return head.join() + _tail.map((c) => _alphabet[c]).join();
  }
}
