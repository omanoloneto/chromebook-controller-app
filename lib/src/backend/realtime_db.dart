// Porta do Realtime Database: só o que o app usa, para o mesmo código rodar
// sobre o plugin (Android) e sobre REST + SSE (Linux, onde o plugin não existe).

import 'dart:async';

abstract interface class RealtimeDb {
  DbRef ref([String? path]);
}

abstract interface class DbQuery {
  Stream<DbEvent> get onValue;
  Stream<DbEvent> get onChildAdded;
  Stream<DbEvent> get onChildRemoved;
  Future<DbSnapshot> get();
  DbQuery orderByKey();
  DbQuery startAt(String key);
  DbQuery endAt(String key);
  DbQuery limitToFirst(int limit);
  DbQuery limitToLast(int limit);
}

abstract interface class DbRef implements DbQuery {
  String? get key;
  DbRef child(String path);
  DbRef push();
  Future<void> set(Object? value);
  Future<void> update(Map<String, Object?> value);
  Future<void> remove();
  Future<TransactionResult> runTransaction(
    Transaction Function(Object? current) handler, {
    bool applyLocally = true,
  });
}

abstract interface class DbSnapshot {
  String? get key;
  Object? get value;
  bool get exists;
  Iterable<DbSnapshot> get children;
}

final class DbEvent {
  const DbEvent(this.snapshot);

  final DbSnapshot snapshot;
}

final class Transaction {
  const Transaction.success(this.value) : aborted = false;
  const Transaction.abort()
      : aborted = true,
        value = null;

  final bool aborted;
  final Object? value;
}

final class TransactionResult {
  const TransactionResult({required this.committed, required this.snapshot});

  final bool committed;
  final DbSnapshot snapshot;
}

abstract final class ServerValue {
  static const Map<String, String> timestamp = {'.sv': 'timestamp'};
}
