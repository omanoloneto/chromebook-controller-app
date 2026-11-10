// Os adaptadores REST contra os emuladores do Firebase, com as regras de
// verdade: o que o servidor de mentira dos outros testes só imita.
// Roda por tool/test-rest-emulator.sh; fora dele, fica de fora.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:controle_de_aula/src/backend/rest/rest_auth.dart';
import 'package:controle_de_aula/src/backend/rest/rest_config.dart';
import 'package:controle_de_aula/src/backend/rest/rest_db.dart';
import 'package:controle_de_aula/src/backend/rest/rest_http.dart';
import 'package:controle_de_aula/src/backend/rest/rest_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart' show until;

const _project = 'demo-cda';
const _bucket = '$_project.appspot.com';

final _databaseHost = Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'];
final _authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
final _storageHost = Platform.environment['FIREBASE_STORAGE_EMULATOR_HOST'];

final class _Client {
  _Client([SessionStore? store]) : store = store ?? MemorySessionStore() {
    final config = RestConfig(
      apiKey: 'demo-key',
      databaseUrl: 'http://$_databaseHost',
      databaseNamespace: '$_project-default-rtdb',
      storageBucket: _bucket,
      identityOrigin: 'http://$_authHost/identitytoolkit.googleapis.com',
      tokenOrigin: 'http://$_authHost/securetoken.googleapis.com',
      storageOrigin: 'http://$_storageHost',
    );
    auth = RestAuth(http: http, config: config, store: this.store);
    db = RestDb(http: http, auth: auth, config: config);
    storage = RestStorage(http: http, auth: auth, config: config);
  }

  final SessionStore store;
  final RestHttp http = RestHttp();
  late final RestAuth auth;
  late final RestDb db;
  late final RestStorage storage;

  String get uid => auth.currentUser!.uid;

  DbRef get home => db.ref('teachers/$uid');

  void close() {
    db.close();
    http.close();
  }
}

void main() {
  final running =
      _databaseHost != null && _authHost != null && _storageHost != null;
  final clients = <_Client>[];
  final subscriptions = <StreamSubscription<DbEvent>>[];

  Future<_Client> signedIn() async {
    final client = _Client();
    clients.add(client);
    await client.auth.signInAnonymously();
    return client;
  }

  List<Object?> collect(
    Stream<DbEvent> stream, {
    bool keys = false,
    List<Object>? errors,
  }) {
    final seen = <Object?>[];
    subscriptions.add(
      stream.listen(
        (event) =>
            seen.add(keys ? event.snapshot.key : event.snapshot.value),
        onError: (Object error) => errors?.add(error),
      ),
    );
    return seen;
  }

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    for (final client in clients) {
      client.close();
    }
    clients.clear();
  });

  final denied = isA<FirebaseException>()
      .having((e) => e.code, 'code', 'permission-denied');

  group(
    'emuladores',
    skip: running ? false : 'rode por tool/test-rest-emulator.sh',
    () {
      test('entra, grava, lê, atualiza e apaga no que é seu', () async {
        final client = await signedIn();
        final node = client.home.child('prefs');

        await node.set({'theme': 'dark', 'size': 2});
        expect((await node.get()).value, {'theme': 'dark', 'size': 2});

        await node.update({'size': 3, 'extra': true});
        expect(
          (await node.get()).value,
          {'theme': 'dark', 'size': 3, 'extra': true},
        );

        await node.remove();
        final gone = await node.get();
        expect(gone.exists, isFalse);
        expect(gone.key, 'prefs');
      });

      test('a hora do servidor vira número na gravação', () async {
        final client = await signedIn();
        final node = client.home.child('at');

        await node.set(ServerValue.timestamp);

        final value = (await node.get()).value;
        expect(value, isA<int>());
        final drift = DateTime.now().millisecondsSinceEpoch - (value! as int);
        expect(drift.abs(), lessThan(60000));
      });

      test('as regras de verdade negam o que é de outro', () async {
        final client = await signedIn();
        final other = client.db.ref('teachers/someone-else/prefs');

        await expectLater(other.get(), throwsA(denied));
        await expectLater(other.set('x'), throwsA(denied));
        expect(client.auth.currentUser, isNotNull);
      });

      test('transações concorrentes não perdem incremento', () async {
        final client = await signedIn();
        final counter = client.home.child('counter');
        Transaction bump(Object? current) =>
            Transaction.success(((current as int?) ?? 0) + 1);

        final results = await Future.wait([
          for (var i = 0; i < 5; i++) counter.runTransaction(bump),
        ]);

        expect(results.every((result) => result.committed), isTrue);
        expect((await counter.get()).value, 5);
      });

      test('push ordena por chegada e as consultas recortam por chave',
          () async {
        final client = await signedIn();
        final list = client.home.child('list');
        final keys = <String>[];
        for (var i = 0; i < 5; i++) {
          final item = list.push();
          await item.set('item-$i');
          keys.add(item.key!);
        }
        expect(keys, [...keys]..sort());

        List<Object?> values(DbSnapshot snapshot) =>
            [for (final child in snapshot.children) child.value];

        expect(
          values(await list.orderByKey().limitToLast(2).get()),
          ['item-3', 'item-4'],
        );
        expect(
          values(await list.orderByKey().limitToFirst(1).get()),
          ['item-0'],
        );
        expect(
          values(await list.orderByKey().startAt(keys[3]).get()),
          ['item-3', 'item-4'],
        );
        expect(
          values(await list.orderByKey().endAt(keys[1]).get()),
          ['item-0', 'item-1'],
        );
      });

      test('escuta de valor acompanha gravação, atualização e remoção',
          () async {
        final client = await signedIn();
        final node = client.home.child('live');
        final seen = collect(node.onValue);
        await until(() => seen.length == 1);

        await node.set({'a': 1});
        await until(() => seen.length == 2);
        await node.update({'b': 2});
        await until(() => seen.length == 3);
        await node.child('a').remove();
        await until(() => seen.length == 4);
        await node.remove();
        await until(() => seen.length == 5);

        expect(seen, [
          null,
          {'a': 1},
          {'a': 1, 'b': 2},
          {'b': 2},
          null,
        ]);
      });

      test('escuta de filhos vê quem já estava, quem entra e quem sai',
          () async {
        final client = await signedIn();
        final list = client.home.child('queue');
        await list.child('a').set(1);
        final added = collect(list.onChildAdded, keys: true);
        final removed = collect(list.onChildRemoved, keys: true);
        await until(() => added.length == 1);

        await list.child('b').set(2);
        await until(() => added.length == 2);
        await list.child('a').remove();
        await until(() => removed.length == 1);

        expect(added, ['a', 'b']);
        expect(removed, ['a']);
      });

      test('escuta sem permissão recebe o erro das regras', () async {
        final client = await signedIn();
        final errors = <Object>[];
        final seen = collect(
          client.db.ref('teachers/someone-else').onValue,
          errors: errors,
        );

        await until(() => errors.isNotEmpty);

        expect(errors.single, denied);
        expect(seen, isEmpty);
      });

      test('a sessão guardada volta sem entrar de novo', () async {
        final first = await signedIn();
        await first.home.child('kept').set('yes');

        final again = _Client(MemorySessionStore(first.store.load()));
        clients.add(again);

        expect(again.uid, first.uid);
        expect((await again.home.child('kept').get()).value, 'yes');
      });

      test('.info/connected confirma o servidor ao alcance', () async {
        final client = await signedIn();
        final seen = collect(client.db.ref('.info/connected').onValue);
        await client.home.child('ping').set(1);

        await until(() => seen.isNotEmpty && seen.last == true);
      });

      group('storage', () {
        const day = '2026-11-10';
        const file = '1794300000000_AAAAAAAAAAAAAAAAAAAAAA.bin';
        final payload = Uint8List.fromList(List.generate(2048, (i) => i % 251));

        // O arquivo nasce pelo PC do aluno: aqui, a própria conta faz esse
        // papel direto na API, porque o app só baixa e apaga.
        Future<void> upload(_Client client, String path) async {
          final reply = await client.http.send(
            'POST',
            Uri.parse('http://$_storageHost/v0/b/$_bucket/o')
                .replace(queryParameters: {'name': path}),
            headers: {
              'authorization': 'Firebase ${await client.auth.idTokenOrNull()}',
              'content-type': 'application/octet-stream',
            },
            body: payload,
          );
          expect(reply.status, 200, reason: utf8.decode(reply.body));
        }

        test('conta da escola baixa e apaga; depois o arquivo não existe',
            () async {
          final client = await signedIn();
          final link = await client.auth.linkGoogle(
            jsonEncode({
              'sub': 'google-${client.uid}',
              'email': '${client.uid.toLowerCase()}@escola.example',
              'email_verified': true,
            }),
          );
          expect(link, GoogleLink.linked);
          expect(client.auth.currentUser!.hasGoogle, isTrue);
          final path = 'fotos/${client.uid}/$day/$file';
          await upload(client, path);

          expect(await client.storage.getData(path, 1 << 20), payload);
          await expectLater(
            client.storage.getData(path, 100),
            throwsA(
              isA<FirebaseException>()
                  .having((e) => e.code, 'code', 'download-size-exceeded'),
            ),
          );

          await client.storage.delete(path);
          await expectLater(
            client.storage.getData(path, 1 << 20),
            throwsA(
              isA<FirebaseException>()
                  .having((e) => e.code, 'code', 'object-not-found'),
            ),
          );
        });

        test('conta anônima não baixa foto', () async {
          final client = await signedIn();
          final path = 'fotos/${client.uid}/$day/$file';
          await upload(client, path);

          await expectLater(
            client.storage.getData(path, 1 << 20),
            throwsA(
              isA<FirebaseException>()
                  .having((e) => e.code, 'code', 'unauthorized'),
            ),
          );
        });
      });
    },
  );
}
