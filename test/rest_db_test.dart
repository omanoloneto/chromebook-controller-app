// Realtime Database por REST: leitura, escrita, consulta, push, transação e
// os erros que o resto do app espera do SDK.

import 'dart:io';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  late RestHarness rest;

  Future<void> start({
    Map<String, Object?>? session = RestHarness.savedSession,
    String? namespace,
  }) async {
    rest = await RestHarness.start(session: session, namespace: namespace);
  }

  tearDown(() => rest.stop());

  TypeMatcher<FirebaseException> dbError(String code) =>
      isA<FirebaseException>()
      .having((e) => e.plugin, 'plugin', 'firebase_database')
      .having((e) => e.code, 'code', code);

  const denied = Reply.json({'error': 'Permission denied'}, status: 401);
  const expired = Reply.json({'error': 'Auth token is expired'}, status: 401);

  group('leitura', () {
    test('get lê o nó com o token da conta', () async {
      await start();
      rest.fake.onCall = (_) => const Reply.json({
            'label': 'PC 7',
            'tabs': ['a', 'b'],
          });

      final snapshot = await rest.db.ref('devices/pc1/meta').get();

      expect(snapshot.key, 'meta');
      expect(snapshot.exists, isTrue);
      expect(snapshot.value, {
        'label': 'PC 7',
        'tabs': ['a', 'b'],
      });
      final request = rest.fake.calls.single;
      expect(request.method, 'GET');
      expect(request.path, '/db/devices/pc1/meta.json');
      expect(request.query, {'auth': rest.fake.accounts.lastToken});
    });

    test('nó vazio não existe', () async {
      await start();
      final snapshot = await rest.db.ref('nothing').get();
      expect(snapshot.exists, isFalse);
      expect(snapshot.value, isNull);
    });

    test('sem conta a leitura vai sem token', () async {
      await start(session: null);
      await rest.db.ref('home/menu').get();
      expect(rest.fake.calls.single.query, isEmpty);
      expect(rest.fake.accounts.refreshes, 0);
    });

    test('o emulador recebe o banco em ns', () async {
      await start(namespace: 'demo-cda-default-rtdb');
      await rest.db.ref('a').get();
      expect(
        rest.fake.calls.single.query,
        containsPair('ns', 'demo-cda-default-rtdb'),
      );
    });

    test('chave com caractere especial vai codificada', () async {
      await start();
      await rest.db.ref('school/members').child('ana maria@x,com').get();
      final request = rest.fake.calls.single;
      expect(request.uri.pathSegments, [
        'db',
        'school',
        'members',
        'ana maria@x,com.json',
      ]);
      expect(request.path, isNot(contains(' ')));
    });

    test('consulta por chave manda ordem, faixa e limite', () async {
      await start();
      rest.fake.onCall = (_) => const Reply.json({
            '1794269619000': {'n': 1},
          });

      final snapshot = await rest.db
          .ref('archive/pc1')
          .orderByKey()
          .startAt('1794269619000')
          .endAt('1794269619999')
          .limitToLast(1)
          .get();

      expect(snapshot.children.single.key, '1794269619000');
      expect(rest.fake.calls.single.query, {
        'orderBy': r'"$key"',
        'startAt': '"1794269619000"',
        'endAt': '"1794269619999"',
        'limitToLast': '1',
        'auth': rest.fake.accounts.lastToken,
      });

      await rest.db.ref('archive/pc1').startAt('5').limitToFirst(2).get();
      expect(rest.fake.calls.last.query, containsPair('limitToFirst', '2'));
      expect(rest.fake.calls.last.query, containsPair('orderBy', r'"$key"'));
    });

    test('escutar consulta filtrada não é suportado', () async {
      await start();
      expect(
        () => rest.db.ref('archive/pc1').limitToLast(1).onValue,
        throwsUnsupportedError,
      );
    });
  });

  group('escrita', () {
    test('set, update e remove usam PUT, PATCH e DELETE sem eco', () async {
      await start();
      rest.fake.onCall = (_) => const Reply(204);
      final ref = rest.db.ref('teachers/uid-1/prefs');

      await ref.set({'theme': 'dark', 'at': ServerValue.timestamp});
      await ref.update({'theme': 'light', 'old': null});
      await ref.set(null);
      await ref.remove();

      final calls = rest.fake.calls;
      expect(calls.map((c) => c.method), ['PUT', 'PATCH', 'PUT', 'DELETE']);
      expect(calls.map((c) => c.path).toSet(), {
        '/db/teachers/uid-1/prefs.json',
      });
      expect(calls.every((c) => c.query['print'] == 'silent'), isTrue);
      expect(calls[0].json, {
        'theme': 'dark',
        'at': {'.sv': 'timestamp'},
      });
      expect(calls[0].headers.contentType?.mimeType, 'application/json');
      expect(calls[1].json, {'theme': 'light', 'old': null});
      expect(calls[2].body, 'null');
      expect(calls[3].body, isEmpty);
    });

    test('push gera a chave no cliente e escreve no filho', () async {
      await start();
      rest.fake.onCall = (_) => const Reply(204);
      final list = rest.db.ref('devices/pc1/cmd');

      final first = list.push();
      final second = list.push();
      await first.set('envelope');

      expect(first.key, hasLength(20));
      expect(first.key!.compareTo(second.key!), lessThan(0));
      final request = rest.fake.calls.single;
      expect(request.method, 'PUT');
      expect(request.path, '/db/devices/pc1/cmd/${first.key}.json');
      expect(request.json, 'envelope');
    });

    test('.info não se escreve nem se lê por get', () async {
      await start();
      expect(() => rest.db.ref('.info/connected').get(), throwsUnsupportedError);
    });
  });

  group('erros', () {
    test('negado pelas regras não gasta renovação de token', () async {
      await start();
      await rest.auth.idTokenOrNull();
      rest.fake.onCall = (_) => denied;

      await expectLater(
        rest.db.ref('school/members/x').get(),
        throwsA(dbError('permission-denied')),
      );
      await expectLater(
        rest.db.ref('devices/pc1/cmd').set(1),
        throwsA(dbError('permission-denied')),
      );
      expect(rest.fake.accounts.refreshes, 1);
      expect(rest.fake.calls, hasLength(2));
    });

    test('token vencido renova e repete a chamada', () async {
      await start();
      final tokens = <String?>[];
      rest.fake.onCall = (request) {
        tokens.add(request.query['auth']);
        return tokens.length == 1 ? expired : const Reply.json('ok');
      };

      final snapshot = await rest.db.ref('a').get();

      expect(snapshot.value, 'ok');
      expect(tokens, hasLength(2));
      expect(tokens.first, isNot(tokens.last));
      expect(rest.fake.accounts.refreshes, 2);
    });

    test('recusado mesmo com token novo é negado', () async {
      await start();
      rest.fake.onCall = (_) => expired;
      await expectLater(
        rest.db.ref('a').get(),
        throwsA(dbError('permission-denied')),
      );
      expect(rest.fake.calls, hasLength(2));
    });

    test('403 é negado', () async {
      await start();
      rest.fake.onCall = (_) => const Reply.json(null, status: 403);
      await expectLater(
        rest.db.ref('a').get(),
        throwsA(dbError('permission-denied')),
      );
    });

    test('status inesperado sai como unknown, sem a URL', () async {
      await start();
      rest.fake.onCall = (_) => const Reply.json(null, status: 500);
      await expectLater(
        rest.db.ref('a').get(),
        throwsA(
          dbError('unknown').having((e) => e.message, 'message', 'http_500'),
        ),
      );
    });

    test('portal cativo (200 com HTML) é rede fora, não nó vazio', () async {
      await start();
      rest.fake.onCall = (_) => const Reply(200, html: '<html>login</html>');
      await expectLater(
        rest.db.ref('a').get(),
        throwsA(dbError('unavailable')),
      );
    });

    test('sem rede é unavailable e a mensagem não leva o token', () async {
      await start();
      final token = await rest.auth.idTokenOrNull();
      await rest.fake.stop();

      Object? error;
      try {
        await rest.db.ref('a').get();
      } on FirebaseException catch (e) {
        error = e;
      }

      expect(error, dbError('unavailable'));
      expect('$error', isNot(contains(token!)));
      expect('$error', isNot(contains('auth=')));
    });
  });

  group('transação', () {
    test('grava sobre o valor lido, presa ao ETag', () async {
      await start();
      rest.fake.onCall = (request) => request.method == 'GET'
          ? const Reply.json({'by': 'ana'}, headers: {'etag': 'e1'})
          : Reply.json(request.json);
      Object? seen;

      final result = await rest.db.ref('school/aulas/pc1').runTransaction((
        current,
      ) {
        seen = current;
        return const Transaction.success({'by': 'bia'});
      });

      expect(seen, {'by': 'ana'});
      expect(result.committed, isTrue);
      expect(result.snapshot.value, {'by': 'bia'});
      expect(result.snapshot.key, 'pc1');
      final calls = rest.fake.calls;
      expect(calls.map((c) => c.method), ['GET', 'PUT']);
      expect(calls[0].headers.value('x-firebase-etag'), 'true');
      expect(calls[1].headers.value('if-match'), 'e1');
      expect(calls[1].json, {'by': 'bia'});
      expect(calls[1].query.containsKey('print'), isFalse);
    });

    test('quando outro escreve antes, decide de novo com o valor novo',
        () async {
      await start();
      var puts = 0;
      rest.fake.onCall = (request) {
        if (request.method == 'GET') {
          return const Reply.json(null, headers: {'etag': 'e1'});
        }
        puts++;
        return puts == 1
            ? const Reply.json(
                {'by': 'ana'},
                status: 412,
                headers: {'etag': 'e2'},
              )
            : Reply.json(request.json);
      };
      final seen = <Object?>[];

      final result = await rest.db.ref('school/aulas/pc1').runTransaction((
        current,
      ) {
        seen.add(current);
        return current == null
            ? const Transaction.success({'by': 'bia'})
            : const Transaction.abort();
      });

      expect(seen, [
        null,
        {'by': 'ana'},
      ]);
      expect(result.committed, isFalse);
      expect(result.snapshot.value, {'by': 'ana'});
      expect(puts, 1);
    });

    test('segunda tentativa usa o ETag que veio no conflito', () async {
      await start();
      final matches = <String?>[];
      rest.fake.onCall = (request) {
        if (request.method == 'GET') {
          return const Reply.json(1, headers: {'etag': 'e1'});
        }
        matches.add(request.headers.value('if-match'));
        return matches.length == 1
            ? const Reply.json(5, status: 412, headers: {'etag': 'e2'})
            : Reply.json(request.json);
      };

      final result = await rest.db
          .ref('counter')
          .runTransaction((current) => Transaction.success((current! as int) + 1));

      expect(matches, ['e1', 'e2']);
      expect(result.committed, isTrue);
      expect(result.snapshot.value, 6);
    });

    test('desistir não escreve', () async {
      await start();
      rest.fake.onCall = (_) => const Reply.json('x', headers: {'etag': 'e1'});

      final result = await rest.db
          .ref('a')
          .runTransaction((_) => const Transaction.abort());

      expect(result.committed, isFalse);
      expect(result.snapshot.value, 'x');
      expect(rest.fake.calls.map((c) => c.method), ['GET']);
    });

    test('conflito sem fim desiste com max-retries', () async {
      await start();
      rest.fake.onCall = (request) => request.method == 'GET'
          ? const Reply.json(0, headers: {'etag': 'e'})
          : const Reply.json(0, status: 412, headers: {'etag': 'e'});

      await expectLater(
        rest.db.ref('a').runTransaction((_) => const Transaction.success(1)),
        throwsA(dbError('max-retries')),
      );
      expect(rest.fake.calls.where((c) => c.method == 'PUT'), hasLength(25));
    });

    test('negada pelas regras sai como negada', () async {
      await start();
      rest.fake.onCall = (request) => request.method == 'GET'
          ? const Reply.json(null, headers: {'etag': 'e'})
          : denied;
      await expectLater(
        rest.db.ref('a').runTransaction((_) => const Transaction.success(1)),
        throwsA(dbError('permission-denied')),
      );
    });
  });

  group('.info', () {
    test('connected começa falso, sobe com resposta e cai com falha', () async {
      await start();
      final seen = <Object?>[];
      final subscription = rest.db
          .ref('.info/connected')
          .onValue
          .listen((event) => seen.add(event.snapshot.value));
      addTearDown(subscription.cancel);

      await until(() => seen.length == 1);
      await rest.db.ref('a').get();
      await until(() => seen.length == 2);
      await rest.fake.stop();
      await expectLater(rest.db.ref('a').get(), throwsA(anything));
      await until(() => seen.length == 3);

      expect(seen, [false, true, false]);
    });

    test('serverTimeOffset sai do relógio das respostas', () async {
      await start();
      final ahead = DateTime.now().toUtc().add(const Duration(hours: 1));
      rest.fake.onCall = (_) => Reply.json(
            null,
            headers: {'date': HttpDate.format(ahead)},
          );
      final seen = <int>[];
      final subscription = rest.db
          .ref('.info/serverTimeOffset')
          .onValue
          .listen((event) => seen.add(event.snapshot.value! as int));
      addTearDown(subscription.cancel);

      await rest.db.ref('a').get();
      await until(() => seen.isNotEmpty);
      await rest.db.ref('a').get();

      const hour = 3600000;
      expect(seen.single, inInclusiveRange(hour - 2000, hour + 2000));
    });
  });
}
