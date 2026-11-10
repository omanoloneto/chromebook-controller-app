// Servidor de mentira em loopback para os adaptadores REST: responde o que o
// teste mandar e guarda o que chegou.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/backend/rest/rest_auth.dart';
import 'package:controle_de_aula/src/backend/rest/rest_config.dart';
import 'package:controle_de_aula/src/backend/rest/rest_db.dart';
import 'package:controle_de_aula/src/backend/rest/rest_http.dart';
import 'package:controle_de_aula/src/backend/rest/rest_storage.dart';
import 'package:controle_de_aula/src/backend/rest/rest_streams.dart';

final class Received {
  Received(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;
  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

final class Reply {
  const Reply(
    this.status, {
    this.body,
    this.headers = const {},
    this.html,
    this.bytes,
  });

  const Reply.json(
    Object? value, {
    int status = 200,
    Map<String, String> headers = const {},
  }) : this(status, body: value, headers: headers);

  final int status;
  final Object? body;
  final Map<String, String> headers;
  final String? html;
  final List<int>? bytes;
}

/// Um stream de eventos aberto por um cliente.
final class OpenStream {
  OpenStream(this.request, this._socket) {
    // O socket cru é o único que avisa quando o cliente desliga: o
    // HttpResponse só percebe na escrita seguinte, e às vezes nem nela.
    _socket.listen(
      (_) {},
      onDone: _markClosed,
      onError: (Object _) => _markClosed(),
    );
  }

  final Received request;
  final Socket _socket;
  bool closed = false;

  void _markClosed() {
    closed = true;
    _socket.destroy();
  }

  Future<void> send(String event, Object? data) async {
    _socket.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
    await _socket.flush();
  }

  Future<void> put(String path, Object? data) =>
      send('put', {'path': path, 'data': data});

  Future<void> patch(String path, Map<String, Object?> data) =>
      send('patch', {'path': path, 'data': data});

  Future<void> hangUp() async => _markClosed();
}

/// Identity Toolkit + Secure Token de mentira: cada token emitido é diferente.
final class FakeAccounts {
  String uid = 'uid-1';
  String expiresIn = '3600';
  Map<String, Object?> claims = const {};
  int signUps = 0;
  int refreshes = 0;
  int _minted = 0;
  String? lastToken;
  Reply? refreshFailure;
  Reply Function(Received request)? onIdp;

  String mint() =>
      lastToken = fakeJwt({'user_id': uid, 'n': ++_minted, ...claims});

  Map<String, Object?> identity() => {
        'localId': uid,
        'idToken': mint(),
        'refreshToken': 'refresh-$uid',
        'expiresIn': expiresIn,
      };

  Reply handle(Received request) {
    if (request.path.endsWith('accounts:signUp')) {
      signUps++;
      return Reply.json(identity());
    }
    if (request.path.endsWith('accounts:signInWithIdp')) {
      return onIdp?.call(request) ?? Reply.json(identity());
    }
    if (request.path.endsWith('/v1/token')) {
      refreshes++;
      return refreshFailure ??
          Reply.json({
            'user_id': uid,
            'id_token': mint(),
            'refresh_token': 'refresh-$uid',
            'expires_in': expiresIn,
          });
    }
    return const Reply(404);
  }
}

final class FakeFirebase {
  FakeFirebase._(this._server);

  static Future<FakeFirebase> start() async {
    final fake = FakeFirebase._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen(fake._serve);
    return fake;
  }

  final HttpServer _server;
  final List<Received> requests = [];
  final List<OpenStream> streams = [];
  final FakeAccounts accounts = FakeAccounts();

  /// Resposta das chamadas de banco e de arquivos.
  FutureOr<Reply> Function(Received request) onCall =
      (_) => const Reply.json(null);

  /// Resposta à abertura de stream: null aceita, um Reply recusa.
  Reply? Function(Received request) onStream = (_) => null;

  String get origin => 'http://127.0.0.1:${_server.port}';

  List<OpenStream> get liveStreams =>
      streams.where((stream) => !stream.closed).toList();

  Future<void> _serve(HttpRequest request) async {
    final received = Received(
      request.method,
      request.uri,
      request.headers,
      await utf8.decodeStream(request),
    );
    requests.add(received);
    final response = request.response;
    final wantsStream =
        request.headers.value(HttpHeaders.acceptHeader) == 'text/event-stream';
    if (wantsStream) {
      final refusal = onStream(received);
      if (refusal == null) {
        response.headers.contentType = ContentType('text', 'event-stream');
        response.headers.chunkedTransferEncoding = false;
        response.persistentConnection = false;
        streams.add(OpenStream(received, await response.detachSocket()));
        return;
      }
      return _write(response, refusal);
    }
    final toAccounts = received.path.startsWith('/identity/') ||
        received.path.startsWith('/token/');
    return _write(
      response,
      toAccounts ? accounts.handle(received) : await onCall(received),
    );
  }

  /// Chamadas de banco e de arquivos, sem as de conta.
  List<Received> get calls => requests
      .where(
        (request) =>
            !request.path.startsWith('/identity/') &&
            !request.path.startsWith('/token/'),
      )
      .toList();

  Future<void> _write(HttpResponse response, Reply reply) async {
    response.statusCode = reply.status;
    reply.headers.forEach(response.headers.set);
    final html = reply.html;
    final bytes = reply.bytes;
    if (html != null) {
      response.headers.contentType = ContentType.html;
      response.write(html);
    } else if (bytes != null) {
      response.headers.contentType = ContentType.binary;
      response.add(bytes);
    } else if (reply.status != HttpStatus.noContent) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(reply.body));
    }
    await response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

/// Espera a condição valer, sem depender de relógio fixo.
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition never held');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Token com a forma de um JWT do Firebase (sem assinatura de verdade).
String fakeJwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

const StreamTimings fastTimings = StreamTimings(
  watchdog: Duration(milliseconds: 400),
  minBackoff: Duration(milliseconds: 10),
  maxBackoff: Duration(milliseconds: 40),
);

/// Os adaptadores REST montados contra o servidor de mentira.
final class RestHarness {
  RestHarness._(this.fake, this.store, this.http, this.auth, this.db)
      : storage = RestStorage(http: http, auth: auth, config: _config(fake));

  static Future<RestHarness> start({
    Map<String, Object?>? session,
    String? namespace,
    StreamTimings timings = fastTimings,
  }) async {
    final fake = await FakeFirebase.start();
    final store = MemorySessionStore(session);
    final http = RestHttp();
    final config = _config(fake, namespace);
    final auth = RestAuth(http: http, config: config, store: store);
    return RestHarness._(
      fake,
      store,
      http,
      auth,
      RestDb(http: http, auth: auth, config: config, timings: timings),
    );
  }

  static const Map<String, Object?> savedSession = {
    'uid': 'uid-1',
    'refreshToken': 'refresh-uid-1',
  };

  final FakeFirebase fake;
  final MemorySessionStore store;
  final RestHttp http;
  final RestAuth auth;
  final RestDb db;
  final RestStorage storage;

  static RestConfig _config(FakeFirebase fake, [String? namespace]) =>
      RestConfig(
        apiKey: 'key',
        databaseUrl: '${fake.origin}/db',
        databaseNamespace: namespace,
        storageBucket: 'bucket',
        identityOrigin: '${fake.origin}/identity',
        tokenOrigin: '${fake.origin}/token',
        storageOrigin: '${fake.origin}/storage',
      );

  Future<void> stop() async {
    db.close();
    http.close();
    await fake.stop();
  }
}
