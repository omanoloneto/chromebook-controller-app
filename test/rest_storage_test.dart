// Arquivos do Storage por REST: baixar com teto de tamanho e apagar.

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  late RestHarness rest;

  setUp(() async {
    rest = await RestHarness.start(session: RestHarness.savedSession);
  });

  tearDown(() => rest.stop());

  TypeMatcher<FirebaseException> storageError(String code) =>
      isA<FirebaseException>()
      .having((e) => e.plugin, 'plugin', 'firebase_storage')
      .having((e) => e.code, 'code', code);

  const path = 'fotos/uid-pc/2026-11-10/a b.bin';

  test('baixa os bytes com o token no cabeçalho', () async {
    rest.fake.onCall = (_) => const Reply(200, bytes: [1, 2, 3]);

    final data = await rest.storage.getData(path, 10);

    expect(data, [1, 2, 3]);
    final request = rest.fake.calls.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      '/storage/v0/b/bucket/o/fotos%2Fuid-pc%2F2026-11-10%2Fa%20b.bin',
    );
    expect(request.query, {'alt': 'media'});
    expect(
      request.headers.value('authorization'),
      'Firebase ${rest.fake.accounts.lastToken}',
    );
  });

  test('arquivo maior que o teto é recusado', () async {
    rest.fake.onCall = (_) => Reply(200, bytes: List.filled(11, 0));
    await expectLater(
      rest.storage.getData(path, 10),
      throwsA(storageError('download-size-exceeded')),
    );
  });

  test('apaga sem pedir o conteúdo', () async {
    rest.fake.onCall = (_) => const Reply(204);

    await rest.storage.delete(path);

    final request = rest.fake.calls.single;
    expect(request.method, 'DELETE');
    expect(request.query, isEmpty);
  });

  test('erros do servidor viram os códigos do SDK', () async {
    for (final (status, code) in [
      (404, 'object-not-found'),
      (403, 'unauthorized'),
      (500, 'unknown'),
    ]) {
      rest.fake.onCall = (_) => Reply.json(null, status: status);
      await expectLater(
        rest.storage.getData(path, 10),
        throwsA(storageError(code)),
        reason: '$status',
      );
    }
  });

  test('401 renova o token uma vez antes de desistir', () async {
    final tokens = <String?>[];
    rest.fake.onCall = (request) {
      tokens.add(request.headers.value('authorization'));
      return tokens.length == 1
          ? const Reply.json(null, status: 401)
          : const Reply(200, bytes: [7]);
    };

    expect(await rest.storage.getData(path, 10), [7]);
    expect(tokens, hasLength(2));
    expect(tokens.first, isNot(tokens.last));

    rest.fake.onCall = (_) => const Reply.json(null, status: 401);
    await expectLater(
      rest.storage.getData(path, 10),
      throwsA(storageError('unauthorized')),
    );
  });

  test('sem rede o erro é o de tentativas esgotadas', () async {
    await rest.auth.idTokenOrNull();
    await rest.fake.stop();
    await expectLater(
      rest.storage.getData(path, 10),
      throwsA(storageError('retry-limit-exceeded')),
    );
  });
}
