// Monta as portas sobre REST + SSE: Dart puro, para o Linux, onde os plugins
// do Firebase não existem.

import 'dart:io';

import '../backend.dart';
import 'rest_auth.dart';
import 'rest_config.dart';
import 'rest_db.dart';
import 'rest_http.dart';
import 'rest_storage.dart';
import 'rest_streams.dart';

Backend restBackend(
  RestConfig config, {
  required SessionStore store,
  HttpClient? client,
  StreamTimings timings = const StreamTimings(),
}) {
  final http = RestHttp(client: client);
  final auth = RestAuth(http: http, config: config, store: store);
  return Backend(
    db: RestDb(http: http, auth: auth, config: config, timings: timings),
    auth: auth,
    storage: RestStorage(http: http, auth: auth, config: config),
  );
}
