// Storage por REST (API v0), para o Linux.

import 'dart:typed_data';

import '../backend.dart';
import 'rest_auth.dart';
import 'rest_config.dart';
import 'rest_http.dart';

final class RestStorage implements BlobStorage {
  RestStorage({
    required RestHttp http,
    required RestAuth auth,
    required RestConfig config,
  })  : _http = http,
        _auth = auth,
        _config = config;

  final RestHttp _http;
  final RestAuth _auth;
  final RestConfig _config;

  @override
  Future<Uint8List?> getData(String path, int maxSize) async {
    final reply = await _call('GET', path, maxSize, {'alt': 'media'});
    return reply.body;
  }

  @override
  Future<void> delete(String path) => _call('DELETE', path);

  Future<HttpReply> _call(
    String method,
    String path, [
    int? maxBytes,
    Map<String, String>? query,
  ]) async {
    final bucket = Uri.encodeComponent(_config.storageBucket);
    final uri = Uri.parse(
      '${_config.storageOrigin}/v0/b/$bucket/o/${Uri.encodeComponent(path)}',
    ).replace(queryParameters: query);
    try {
      var token = await _auth.idTokenOrNull();
      var reply = await _send(method, uri, token, maxBytes);
      if (reply.status == 401 && token != null) {
        token = await _auth.idTokenOrNull(force: true);
        reply = await _send(method, uri, token, maxBytes);
      }
      return switch (reply.status) {
        >= 200 && < 300 => reply,
        404 => throw _error('object-not-found'),
        401 || 403 => throw _error('unauthorized'),
        _ => throw _error('unknown', 'http_${reply.status}'),
      };
    } on NetworkFailure catch (e) {
      throw _error('retry-limit-exceeded', e.reason);
    } on BodyTooLarge {
      throw _error('download-size-exceeded');
    }
  }

  Future<HttpReply> _send(
    String method,
    Uri uri,
    String? token,
    int? maxBytes,
  ) =>
      _http.send(
        method,
        uri,
        headers: {if (token != null) 'authorization': 'Firebase $token'},
        maxBytes: maxBytes,
      );

  static FirebaseException _error(String code, [String? message]) =>
      FirebaseException(
        plugin: 'firebase_storage',
        code: code,
        message: message,
      );
}
