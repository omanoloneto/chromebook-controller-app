// O servidor do app (banco, conta e arquivos) atrás de portas próprias.
// Os erros continuam sendo FirebaseException nas duas plataformas.

import 'auth_gateway.dart';
import 'blob_storage.dart';
import 'realtime_db.dart';

export 'package:firebase_core/firebase_core.dart' show FirebaseException;

export 'auth_gateway.dart';
export 'blob_storage.dart';
export 'realtime_db.dart';

final class Backend {
  const Backend({required this.db, required this.auth, required this.storage});

  final RealtimeDb db;
  final AuthGateway auth;
  final BlobStorage storage;

  static Backend? _instance;

  static Backend get instance =>
      _instance ?? (throw StateError('backend_not_open'));

  static set instance(Backend backend) => _instance = backend;
}
