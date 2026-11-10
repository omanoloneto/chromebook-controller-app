// HTTP dos adaptadores REST: dart:io puro, com prazo, e de quebra o estado da
// rede e o relógio do servidor que o SDK daria por .info.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const Duration kFetchTimeout = Duration(seconds: 20);

final class NetworkFailure implements Exception {
  const NetworkFailure(this.reason);

  final String reason;

  @override
  String toString() => 'NetworkFailure($reason)';
}

final class BodyTooLarge implements Exception {
  const BodyTooLarge();
}

final class HttpReply {
  HttpReply(this.status, this._headers, this.body);

  final int status;
  final HttpHeaders _headers;
  final Uint8List body;

  String? header(String name) => _headers.value(name);

  bool get isJson => _headers.contentType?.subType == 'json';

  /// Corpo JSON; null quando vazio ou ilegível.
  Object? get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> get jsonMap {
    final value = json;
    return value is Map<String, Object?> ? value : const {};
  }
}

/// Rede vista pelas chamadas: alimenta .info/connected e
/// .info/serverTimeOffset, que no Linux não vêm de SDK nenhum.
final class LinkMonitor {
  static const int _offsetToleranceMs = 2000;

  bool _online = false;
  int? _offsetMs;
  final StreamController<bool> _onlineChanges = StreamController.broadcast();
  final StreamController<int> _offsetChanges = StreamController.broadcast();

  bool get online => _online;
  int? get offsetMs => _offsetMs;

  Stream<bool> get onlineValues => _replay(() => _online, _onlineChanges.stream);
  Stream<int> get offsetValues => _replay(() => _offsetMs, _offsetChanges.stream);

  void reachable(bool value) {
    if (value == _online) return;
    _online = value;
    _onlineChanges.add(value);
  }

  void serverDate(DateTime? date, int sentMs, int receivedMs) {
    if (date == null) return;
    // O cabeçalho Date vem truncado no segundo: +500 ms centra o erro.
    final offset =
        date.millisecondsSinceEpoch + 500 - (sentMs + receivedMs) ~/ 2;
    final current = _offsetMs;
    if (current != null && (offset - current).abs() <= _offsetToleranceMs) {
      return;
    }
    _offsetMs = offset;
    _offsetChanges.add(offset);
  }

  static Stream<T> _replay<T extends Object>(
    T? Function() current,
    Stream<T> changes,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        final value = current();
        if (value != null) controller.add(value);
        subscription = changes.listen(controller.add);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}

final class RestHttp {
  RestHttp({HttpClient? client, LinkMonitor? monitor})
      : _client = client ?? (HttpClient()..connectionTimeout = kFetchTimeout),
        monitor = monitor ?? LinkMonitor();

  final HttpClient _client;
  final LinkMonitor monitor;

  Future<HttpReply> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
    int? maxBytes,
  }) =>
      _guard(() async {
        final request = await _client.openUrl(method, uri);
        headers.forEach(request.headers.set);
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
          if (maxBytes != null && bytes.length > maxBytes) {
            throw const BodyTooLarge();
          }
        }
        return (
          HttpReply(response.statusCode, response.headers, bytes.takeBytes()),
          response.headers,
        );
      });

  /// Abre um stream de eventos; o corpo fica com quem chamou.
  Future<HttpClientResponse> openStream(Uri uri) => _guard(() async {
        final request = await _client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        final response = await request.close();
        return (response, response.headers);
      });

  // A mensagem do erro nunca leva a URL: ela carrega o token da conta.
  Future<T> _guard<T>(Future<(T, HttpHeaders)> Function() exchange) async {
    final sentMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final (result, headers) = await exchange().timeout(kFetchTimeout);
      monitor.reachable(true);
      monitor.serverDate(
        _date(headers),
        sentMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      return result;
    } on BodyTooLarge {
      rethrow;
    } on Exception catch (e) {
      monitor.reachable(false);
      throw NetworkFailure(e.runtimeType.toString());
    }
  }

  static DateTime? _date(HttpHeaders headers) {
    try {
      return headers.date;
    } on Exception {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
