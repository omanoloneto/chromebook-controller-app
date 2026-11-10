// Conta do professor por REST: entrar, renovar o token, conta morta e o
// vínculo com a conta Google.

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  late RestHarness rest;

  Future<void> start({Map<String, Object?>? session}) async {
    rest = await RestHarness.start(session: session);
  }

  tearDown(() => rest.stop());

  TypeMatcher<FirebaseException> authError(String code) =>
      isA<FirebaseException>()
      .having((e) => e.plugin, 'plugin', 'firebase_auth')
      .having((e) => e.code, 'code', code);

  test('entrar como anônimo cria a conta e guarda a sessão', () async {
    await start();
    expect(rest.auth.currentUser, isNull);

    final user = await rest.auth.signInAnonymously();

    expect(user.uid, 'uid-1');
    expect(user.hasGoogle, isFalse);
    expect(user.googleEmail, isNull);
    expect(rest.auth.currentUser?.uid, 'uid-1');
    expect(rest.store.load(), containsPair('refreshToken', 'refresh-uid-1'));
    final request = rest.fake.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/identity/v1/accounts:signUp');
    expect(request.query, {'key': 'key'});
    expect(request.json, {'returnSecureToken': true});
    expect(await rest.auth.idTokenOrNull(), rest.fake.accounts.lastToken);
    expect(rest.fake.accounts.refreshes, 0);
  });

  test('sessão guardada volta sem rede, e o token sai da renovação', () async {
    await start(session: RestHarness.savedSession);
    expect(rest.auth.currentUser?.uid, 'uid-1');
    expect(rest.fake.requests, isEmpty);

    final token = await rest.auth.idTokenOrNull();

    expect(token, rest.fake.accounts.lastToken);
    final request = rest.fake.requests.single;
    expect(request.path, '/token/v1/token');
    expect(request.query, {'key': 'key'});
    expect(
      request.headers.contentType?.mimeType,
      'application/x-www-form-urlencoded',
    );
    expect(Uri(query: request.body).queryParameters, {
      'grant_type': 'refresh_token',
      'refresh_token': 'refresh-uid-1',
    });
  });

  test('token fresco é reaproveitado; pedidos juntos renovam uma vez só',
      () async {
    await start(session: RestHarness.savedSession);

    final tokens = await Future.wait([
      rest.auth.idTokenOrNull(),
      rest.auth.idTokenOrNull(),
      rest.auth.idTokenOrNull(),
    ]);
    await rest.auth.idTokenOrNull();

    expect(tokens.toSet(), hasLength(1));
    expect(rest.fake.accounts.refreshes, 1);
  });

  test('refreshIdToken renova mesmo com token fresco', () async {
    await start();
    final user = await rest.auth.signInAnonymously();
    final before = await rest.auth.idTokenOrNull();

    await user.refreshIdToken();

    expect(rest.fake.accounts.refreshes, 1);
    expect(await rest.auth.idTokenOrNull(), isNot(before));
  });

  test('sem conta não há token nem chamada', () async {
    await start();
    expect(await rest.auth.idTokenOrNull(), isNull);
    expect(rest.fake.requests, isEmpty);
  });

  test('conta morta no servidor é esquecida', () async {
    await start(session: RestHarness.savedSession);
    rest.fake.accounts.refreshFailure = const Reply.json(
      {
        'error': {'message': 'TOKEN_EXPIRED'},
      },
      status: 400,
    );
    var changes = 0;
    rest.auth.accountChanges.listen((_) => changes++);

    await expectLater(
      rest.auth.idTokenOrNull(),
      throwsA(authError('user-token-expired')),
    );

    expect(rest.auth.currentUser, isNull);
    expect(rest.store.load(), isNull);
    await until(() => changes == 1);
  });

  test('falha passageira da renovação não derruba a conta', () async {
    await start(session: RestHarness.savedSession);
    rest.fake.accounts.refreshFailure = const Reply.json(null, status: 503);

    await expectLater(
      rest.auth.idTokenOrNull(),
      throwsA(authError('internal-error')),
    );
    expect(rest.auth.currentUser?.uid, 'uid-1');

    // Um 400 que não fala de conta morta também não.
    rest.fake.accounts.refreshFailure = const Reply.json(
      {
        'error': {'message': 'API_KEY_INVALID'},
      },
      status: 400,
    );
    await expectLater(
      rest.auth.idTokenOrNull(),
      throwsA(authError('internal-error')),
    );
    expect(rest.auth.currentUser?.uid, 'uid-1');
    expect(rest.store.load(), isNotNull);
  });

  test('sem rede o erro é de rede e a conta fica', () async {
    await start(session: RestHarness.savedSession);
    await rest.fake.stop();

    await expectLater(
      rest.auth.idTokenOrNull(),
      throwsA(authError('network-request-failed')),
    );
    expect(rest.auth.currentUser?.uid, 'uid-1');
  });

  group('conta Google', () {
    const google = {
      'email': 'prof@escola.example',
      'firebase': {
        'identities': {
          'google.com': ['123'],
        },
      },
    };

    test('vincula à conta anônima e mantém o uid', () async {
      await start();
      await rest.auth.signInAnonymously();
      final anonymous = rest.fake.accounts.lastToken;
      rest.fake.accounts.claims = google;

      final link = await rest.auth.linkGoogle('google-id-token');

      expect(link, GoogleLink.linked);
      final user = rest.auth.currentUser!;
      expect(user.uid, 'uid-1');
      expect(user.hasGoogle, isTrue);
      expect(user.googleEmail, 'prof@escola.example');
      final request = rest.fake.requests.last;
      expect(request.path, '/identity/v1/accounts:signInWithIdp');
      final body = request.json as Map<String, Object?>;
      expect(body['idToken'], anonymous);
      expect(body['returnSecureToken'], isTrue);
      expect(Uri(query: body['postBody'] as String).queryParameters, {
        'id_token': 'google-id-token',
        'providerId': 'google.com',
      });
    });

    for (final (name, refusal) in [
      (
        'erro 400',
        const Reply.json(
          {
            'error': {'message': 'FEDERATED_USER_ID_ALREADY_LINKED'},
          },
          status: 400,
        ),
      ),
      (
        'aviso dentro de um 200',
        const Reply.json({'errorMessage': 'FEDERATED_USER_ID_ALREADY_LINKED'}),
      ),
    ]) {
      test('Google que já tem conta troca de conta ($name)', () async {
        await start();
        await rest.auth.signInAnonymously();
        var changes = 0;
        rest.auth.accountChanges.listen((_) => changes++);
        final accounts = rest.fake.accounts;
        accounts.onIdp = (request) {
          final body = request.json as Map<String, Object?>;
          if (body.containsKey('idToken')) return refusal;
          accounts
            ..uid = 'uid-google'
            ..claims = google;
          return Reply.json(accounts.identity());
        };

        final link = await rest.auth.linkGoogle('google-id-token');

        expect(link, GoogleLink.switched);
        expect(rest.auth.currentUser?.uid, 'uid-google');
        expect(rest.auth.currentUser?.googleEmail, 'prof@escola.example');
        expect(rest.store.load(), containsPair('uid', 'uid-google'));
        await until(() => changes == 1);
      });
    }

    test('sem conta nenhuma, entra direto com a do Google', () async {
      await start();
      rest.fake.accounts
        ..uid = 'uid-google'
        ..claims = google;

      final link = await rest.auth.linkGoogle('google-id-token');

      expect(link, GoogleLink.switched);
      expect(rest.auth.currentUser?.uid, 'uid-google');
      final body = rest.fake.requests.single.json as Map<String, Object?>;
      expect(body.containsKey('idToken'), isFalse);
    });

    test('token do Google recusado não mexe na conta', () async {
      await start();
      await rest.auth.signInAnonymously();
      rest.fake.accounts.onIdp = (_) => const Reply.json(
            {
              'error': {'message': 'INVALID_IDP_RESPONSE'},
            },
            status: 400,
          );

      await expectLater(
        rest.auth.linkGoogle('bad'),
        throwsA(authError('invalid-credential')),
      );
      expect(rest.auth.currentUser?.uid, 'uid-1');
      expect(rest.auth.currentUser?.hasGoogle, isFalse);
    });
  });
}
