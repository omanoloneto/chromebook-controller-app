// Realtime Database por REST + SSE, para o Linux.

import 'dart:async';
import 'dart:convert';

import '../backend.dart';
import 'rest_auth.dart';
import 'rest_config.dart';
import 'rest_http.dart';
import 'rest_streams.dart';
import 'rest_tree.dart';

// O mesmo teto de tentativas de transação do SDK.
const int _maxTransactionTries = 25;

final class RestDb implements RealtimeDb {
  RestDb({
    required RestHttp http,
    required RestAuth auth,
    required RestConfig config,
    StreamTimings timings = const StreamTimings(),
  })  : _http = http,
        _auth = auth,
        _config = config {
    _hub = StreamHub(http: http, auth: auth, uriFor: _uri, timings: timings);
  }

  final RestHttp _http;
  final RestAuth _auth;
  final RestConfig _config;
  final PushIds _pushIds = PushIds();
  late final StreamHub _hub;

  @override
  DbRef ref([String? path]) => _RestRef(this, splitPath(path));

  void close() => _hub.close();

  Uri _uri(
    List<String> path,
    String? token, [
    Map<String, String> query = const {},
  ]) {
    final namespace = _config.databaseNamespace;
    final encoded = path.map(Uri.encodeComponent).join('/');
    return Uri.parse('${_config.databaseUrl}/$encoded.json').replace(
      queryParameters: {
        ...query,
        if (namespace != null) 'ns': namespace,
        if (token != null) 'auth': token,
      },
    );
  }

  int _serverNowMs() =>
      DateTime.now().millisecondsSinceEpoch + (_http.monitor.offsetMs ?? 0);

  Future<HttpReply> _call(
    String method,
    List<String> path, {
    String? payload,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    bool conditional = false,
  }) async {
    Future<HttpReply> send(String? token) => _http.send(
          method,
          _uri(path, token, query),
          headers: {
            if (payload != null) 'content-type': 'application/json',
            ...headers,
          },
          body: payload == null ? null : utf8.encode(payload),
        );
    try {
      var token = await _auth.idTokenOrNull();
      var reply = await send(token);
      // "Permission denied" é resposta de regra, corriqueira; só o resto do
      // 401 (token vencido) vale uma renovação.
      if (reply.status == 401 && token != null && !_deniedByRules(reply)) {
        token = await _auth.idTokenOrNull(force: true);
        reply = await send(token);
      }
      if (reply.status == 401 || reply.status == 403) {
        throw _error('permission-denied');
      }
      if (reply.status == 204) return reply;
      if (reply.status != 200 && !(conditional && reply.status == 412)) {
        throw _error('unknown', 'http_${reply.status}');
      }
      // Portal cativo responde 200 com HTML: é rede fora, não nó vazio.
      if (!reply.isJson) throw _error('unavailable', 'not_json');
      return reply;
    } on NetworkFailure catch (e) {
      throw _error('unavailable', e.reason);
    }
  }

  static bool _deniedByRules(HttpReply reply) =>
      '${reply.jsonMap['error']}'.toLowerCase().contains('permission denied');

  static FirebaseException _error(String code, [String? message]) =>
      FirebaseException(
        plugin: 'firebase_database',
        code: code,
        message: message,
      );
}

final class _Filter {
  const _Filter({
    this.startAt,
    this.endAt,
    this.limitToFirst,
    this.limitToLast,
  });

  final String? startAt;
  final String? endAt;
  final int? limitToFirst;
  final int? limitToLast;

  bool get isEmpty =>
      startAt == null &&
      endAt == null &&
      limitToFirst == null &&
      limitToLast == null;

  _Filter copyWith({
    String? startAt,
    String? endAt,
    int? limitToFirst,
    int? limitToLast,
  }) =>
      _Filter(
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        limitToFirst: limitToFirst ?? this.limitToFirst,
        limitToLast: limitToLast ?? this.limitToLast,
      );

  Map<String, String> get query => isEmpty
      ? const {}
      : {
          'orderBy': r'"$key"',
          if (startAt != null) 'startAt': jsonEncode(startAt),
          if (endAt != null) 'endAt': jsonEncode(endAt),
          if (limitToFirst != null) 'limitToFirst': '$limitToFirst',
          if (limitToLast != null) 'limitToLast': '$limitToLast',
        };
}

class _RestQuery implements DbQuery {
  _RestQuery(this._db, this._path, [this._filter = const _Filter()]);

  final RestDb _db;
  final List<String> _path;
  final _Filter _filter;

  String? get _key => _path.isEmpty ? null : _path.last;

  bool get _isInfo => _path.isNotEmpty && _path.first == '.info';

  Stream<DbEvent> _listen(ListenKind kind) {
    // O app só filtra em leitura única; filtro em escuta pediria repetir no
    // cliente a ordenação do servidor.
    if (!_filter.isEmpty) throw UnsupportedError('filtered_listen');
    if (_isInfo) throw UnsupportedError('info_listen');
    return _db._hub.listen(_path, kind);
  }

  @override
  Stream<DbEvent> get onValue {
    if (!_isInfo) return _listen(ListenKind.value);
    final monitor = _db._http.monitor;
    final Stream<Object> values = switch (_path.join('/')) {
      '.info/connected' => monitor.onlineValues,
      '.info/serverTimeOffset' => monitor.offsetValues,
      _ => throw UnsupportedError('info_path'),
    };
    return values.map((value) => DbEvent(RestSnapshot(_key, value)));
  }

  @override
  Stream<DbEvent> get onChildAdded => _listen(ListenKind.childAdded);

  @override
  Stream<DbEvent> get onChildRemoved => _listen(ListenKind.childRemoved);

  @override
  Future<DbSnapshot> get() async {
    if (_isInfo) throw UnsupportedError('info_get');
    final reply = await _db._call('GET', _path, query: _filter.query);
    return RestSnapshot.fromJson(_key, reply.json);
  }

  // Por chave é a única ordem que o app usa, e a que a consulta já pede.
  @override
  DbQuery orderByKey() => _RestQuery(_db, _path, _filter);

  @override
  DbQuery startAt(String key) =>
      _RestQuery(_db, _path, _filter.copyWith(startAt: key));

  @override
  DbQuery endAt(String key) =>
      _RestQuery(_db, _path, _filter.copyWith(endAt: key));

  @override
  DbQuery limitToFirst(int limit) =>
      _RestQuery(_db, _path, _filter.copyWith(limitToFirst: limit));

  @override
  DbQuery limitToLast(int limit) =>
      _RestQuery(_db, _path, _filter.copyWith(limitToLast: limit));
}

final class _RestRef extends _RestQuery implements DbRef {
  _RestRef(super.db, super.path);

  static const Map<String, String> _silent = {'print': 'silent'};

  @override
  String? get key => _key;

  @override
  DbRef child(String path) => _RestRef(_db, [..._path, ...splitPath(path)]);

  @override
  DbRef push() =>
      _RestRef(_db, [..._path, _db._pushIds.next(_db._serverNowMs())]);

  @override
  Future<void> set(Object? value) =>
      _db._call('PUT', _path, payload: jsonEncode(value), query: _silent);

  @override
  Future<void> update(Map<String, Object?> value) =>
      _db._call('PATCH', _path, payload: jsonEncode(value), query: _silent);

  @override
  Future<void> remove() => _db._call('DELETE', _path, query: _silent);

  @override
  Future<TransactionResult> runTransaction(
    Transaction Function(Object? current) handler, {
    bool applyLocally = true,
  }) async {
    var reply = await _db._call(
      'GET',
      _path,
      headers: const {'x-firebase-etag': 'true'},
    );
    for (var tries = 0; tries < _maxTransactionTries; tries++) {
      final current = RestSnapshot.fromJson(_key, reply.json);
      final decision = handler(current.value);
      if (decision.aborted) {
        return TransactionResult(committed: false, snapshot: current);
      }
      final written = await _db._call(
        'PUT',
        _path,
        payload: jsonEncode(decision.value),
        headers: {'if-match': reply.header('etag') ?? ''},
        conditional: true,
      );
      if (written.status == 200) {
        return TransactionResult(
          committed: true,
          snapshot: RestSnapshot.fromJson(_key, written.json),
        );
      }
      // 412: outro escreveu antes; a resposta já traz o valor e o ETag novos.
      reply = written;
    }
    throw RestDb._error('max-retries');
  }
}
