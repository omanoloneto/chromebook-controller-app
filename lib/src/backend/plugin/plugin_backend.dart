// Adaptadores das portas sobre os plugins do Firebase (Android).

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_database/firebase_database.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart' as fb;

import '../backend.dart';

Backend pluginBackend() => Backend(
      db: _PluginDb(fb.FirebaseDatabase.instance),
      auth: _PluginAuth(fb.FirebaseAuth.instance),
      storage: _PluginStorage(fb.FirebaseStorage.instance),
    );

class _PluginDb implements RealtimeDb {
  _PluginDb(this._db);

  final fb.FirebaseDatabase _db;

  @override
  DbRef ref([String? path]) => _PluginRef(_db.ref(path));
}

class _PluginQuery implements DbQuery {
  _PluginQuery(this._query);

  final fb.Query _query;

  Stream<DbEvent> _events(Stream<fb.DatabaseEvent> source) =>
      source.map((e) => DbEvent(_PluginSnapshot(e.snapshot)));

  @override
  Stream<DbEvent> get onValue => _events(_query.onValue);

  @override
  Stream<DbEvent> get onChildAdded => _events(_query.onChildAdded);

  @override
  Stream<DbEvent> get onChildRemoved => _events(_query.onChildRemoved);

  @override
  Future<DbSnapshot> get() async => _PluginSnapshot(await _query.get());

  @override
  DbQuery orderByKey() => _PluginQuery(_query.orderByKey());

  @override
  DbQuery startAt(String key) => _PluginQuery(_query.startAt(key));

  @override
  DbQuery endAt(String key) => _PluginQuery(_query.endAt(key));

  @override
  DbQuery limitToFirst(int limit) => _PluginQuery(_query.limitToFirst(limit));

  @override
  DbQuery limitToLast(int limit) => _PluginQuery(_query.limitToLast(limit));
}

class _PluginRef extends _PluginQuery implements DbRef {
  _PluginRef(this._ref) : super(_ref);

  final fb.DatabaseReference _ref;

  @override
  String? get key => _ref.key;

  @override
  DbRef child(String path) => _PluginRef(_ref.child(path));

  @override
  DbRef push() => _PluginRef(_ref.push());

  @override
  Future<void> set(Object? value) => _ref.set(value);

  @override
  Future<void> update(Map<String, Object?> value) => _ref.update(value);

  @override
  Future<void> remove() => _ref.remove();

  @override
  Future<TransactionResult> runTransaction(
    Transaction Function(Object? current) handler, {
    bool applyLocally = true,
  }) async {
    final result = await _ref.runTransaction(
      (current) {
        final decision = handler(current);
        return decision.aborted
            ? fb.Transaction.abort()
            : fb.Transaction.success(decision.value);
      },
      applyLocally: applyLocally,
    );
    return TransactionResult(
      committed: result.committed,
      snapshot: _PluginSnapshot(result.snapshot),
    );
  }
}

class _PluginSnapshot implements DbSnapshot {
  _PluginSnapshot(this._snapshot);

  final fb.DataSnapshot _snapshot;

  @override
  String? get key => _snapshot.key;

  @override
  Object? get value => _snapshot.value;

  @override
  bool get exists => _snapshot.exists;

  @override
  Iterable<DbSnapshot> get children => _snapshot.children.map(_PluginSnapshot.new);
}

class _PluginAuth implements AuthGateway {
  _PluginAuth(this._auth);

  final fb.FirebaseAuth _auth;

  @override
  AuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _PluginUser(user);
  }

  @override
  Future<AuthUser> signInAnonymously() async {
    final user = (await _auth.signInAnonymously()).user;
    if (user == null) throw StateError('auth_anonima_falhou');
    return _PluginUser(user);
  }

  @override
  Future<GoogleLink> linkGoogle(String idToken) async {
    final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
    try {
      // Vincula à conta anônima atual: o uid NÃO muda (pareamentos e
      // histórico continuam valendo).
      await _auth.currentUser!.linkWithCredential(credential);
      return GoogleLink.linked;
    } on fb.FirebaseAuthException catch (e) {
      if (e.code != 'credential-already-in-use' &&
          e.code != 'email-already-in-use') {
        rethrow;
      }
      // Conta já existe (outro celular): assume o uid antigo.
      await _auth.signInWithCredential(credential);
      return GoogleLink.switched;
    }
  }
}

class _PluginUser implements AuthUser {
  _PluginUser(this._user);

  final fb.User _user;

  @override
  String get uid => _user.uid;

  @override
  String? get email => _user.email;

  Iterable<fb.UserInfo> get _google =>
      _user.providerData.where((p) => p.providerId == 'google.com');

  @override
  bool get hasGoogle => _google.isNotEmpty;

  @override
  String? get googleEmail => _google.map((p) => p.email).firstOrNull;

  @override
  Future<void> refreshIdToken() => _user.getIdToken(true);
}

class _PluginStorage implements BlobStorage {
  _PluginStorage(this._storage);

  final fb.FirebaseStorage _storage;

  @override
  Future<Uint8List?> getData(String path, int maxSize) =>
      _storage.ref(path).getData(maxSize);

  @override
  Future<void> delete(String path) => _storage.ref(path).delete();
}
