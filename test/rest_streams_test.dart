// Escuta do banco por SSE: valor inicial, mudanças, eventos de filho, um
// stream por PC, religar sem repetir evento, acesso negado e troca de conta.

import 'dart:async';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:controle_de_aula/src/backend/rest/rest_streams.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  late RestHarness rest;
  final subscriptions = <StreamSubscription<DbEvent>>[];
  final errors = <Object>[];

  Future<void> start({StreamTimings timings = fastTimings}) async {
    rest = await RestHarness.start(
      session: RestHarness.savedSession,
      timings: timings,
    );
  }

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    errors.clear();
    await rest.stop();
  });

  List<Object?> collect(Stream<DbEvent> stream, {bool keys = false}) {
    final seen = <Object?>[];
    subscriptions.add(
      stream.listen(
        (event) => seen.add(
          keys
              ? (event.snapshot.key, event.snapshot.value)
              : event.snapshot.value,
        ),
        onError: errors.add,
      ),
    );
    return seen;
  }

  Future<OpenStream> opened([int count = 1]) async {
    await until(() => rest.fake.streams.length >= count);
    return rest.fake.streams[count - 1];
  }

  // Dá tempo de um evento indevido chegar antes de afirmar que não chegou.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  final denied = isA<FirebaseException>()
      .having((e) => e.plugin, 'plugin', 'firebase_database')
      .having((e) => e.code, 'code', 'permission-denied');

  test('entrega o valor inicial e cada mudança', () async {
    await start();
    final seen = collect(rest.db.ref('teachers/uid-1/prefs').onValue);

    final stream = await opened();
    expect(stream.request.path, '/db/teachers/uid-1/prefs.json');
    expect(stream.request.query, {'auth': rest.fake.accounts.lastToken});
    await stream.put('/', {'theme': 'dark'});
    await until(() => seen.length == 1);
    await stream.put('/theme', 'light');
    await until(() => seen.length == 2);
    await stream.patch('/', {'size': 2, 'theme': null});
    await until(() => seen.length == 3);
    await stream.put('/', null);
    await until(() => seen.length == 4);

    expect(seen, [
      {'theme': 'dark'},
      {'theme': 'light'},
      {'size': 2},
      null,
    ]);
    expect(errors, isEmpty);
  });

  test('nó vazio também avisa, uma vez', () async {
    await start();
    final seen = collect(rest.db.ref('teachers/uid-1/none').onValue);

    final stream = await opened();
    await stream.put('/', null);
    await until(() => seen.length == 1);
    await stream.send('keep-alive', null);
    await stream.put('/', null);
    await settle();

    expect(seen, [null]);
  });

  test('valor denso chega como lista e o snapshot leva a chave', () async {
    await start();
    final seen = collect(rest.db.ref('school/stores').onValue, keys: true);

    final stream = await opened();
    await stream.put('/', {'0': 'a', '1': 'b'});
    await until(() => seen.length == 1);

    final (key, value) = seen.single! as (String?, Object?);
    expect(key, 'stores');
    expect(value, ['a', 'b']);
  });

  test('os nós de um PC dividem um stream só, cada um com a sua parte',
      () async {
    await start();
    final pc = rest.db.ref('devices/pc1');
    final report = collect(pc.child('report').onValue);
    final health = collect(pc.child('health').onValue);
    final lock = collect(pc.child('state/lock').onValue);
    final other = collect(rest.db.ref('devices/pc2/report').onValue);

    await opened(2);
    final stream = rest.fake.streams
        .singleWhere((s) => s.request.path == '/db/devices/pc1.json');
    expect(
      rest.fake.streams.map((s) => s.request.path).toSet(),
      {'/db/devices/pc1.json', '/db/devices/pc2.json'},
    );
    await stream.put('/', {
      'report': 'r1',
      'state': {
        'lock': {'on': true},
      },
    });
    await until(() => report.length == 1 && lock.length == 1);
    await until(() => health.length == 1);

    await stream.put('/health', {'battery': 80});
    await until(() => health.length == 2);
    await stream.patch('/state', {'lock/on': false, 'exam': 'e'});
    await until(() => lock.length == 2);
    await stream.put('/report', 'r1');
    await settle();

    expect(report, ['r1']);
    expect(health, [
      null,
      {'battery': 80},
    ]);
    expect(lock, [
      {'on': true},
      {'on': false},
    ]);
    expect(other, isEmpty);
    expect(rest.fake.streams, hasLength(2));
  });

  test('filhos: os que já existem em ordem, depois quem entra e quem sai',
      () async {
    await start();
    final up = rest.db.ref('devices/pc1/up');
    final added = collect(up.onChildAdded, keys: true);
    final removed = collect(up.onChildRemoved, keys: true);

    final stream = await opened();
    await stream.put('/', {
      'up': {'b': 'second', 'a': 'first'},
    });
    await until(() => added.length == 2);
    await stream.put('/up/c', 'third');
    await until(() => added.length == 3);
    await stream.put('/up/a', 'changed');
    await stream.put('/up/b', null);
    await until(() => removed.length == 1);
    await stream.put('/up', null);
    await until(() => removed.length == 3);

    expect(added, [
      ('a', 'first'),
      ('b', 'second'),
      ('c', 'third'),
    ]);
    expect(removed, [
      ('b', 'second'),
      ('a', 'changed'),
      ('c', 'third'),
    ]);
  });

  test('quem chega depois recebe o valor atual sem abrir outro stream',
      () async {
    await start();
    final report = collect(rest.db.ref('devices/pc1/report').onValue);
    final stream = await opened();
    await stream.put('/', {
      'report': 'r1',
      'ack': {'k': 1},
    });
    await until(() => report.length == 1);

    final late = collect(rest.db.ref('devices/pc1/report').onValue);
    final acks = collect(rest.db.ref('devices/pc1/ack').onChildAdded);
    await until(() => late.length == 1 && acks.length == 1);

    expect(late, ['r1']);
    expect(acks, [1]);
    expect(rest.fake.streams, hasLength(1));
  });

  test('ao religar só avisa do que mudou enquanto esteve fora', () async {
    await start();
    final pc = rest.db.ref('devices/pc1');
    final report = collect(pc.child('report').onValue);
    final health = collect(pc.child('health').onValue);
    final acks = collect(pc.child('ack').onChildAdded, keys: true);
    final first = await opened();
    await first.put('/', {
      'report': 'r1',
      'health': 'h1',
      'ack': {'a': 1},
    });
    await until(() => report.length == 1 && acks.length == 1);

    await first.hangUp();
    final second = await opened(2);
    await second.put('/', {
      'report': 'r1',
      'health': 'h2',
      'ack': {'a': 1, 'b': 2},
    });
    await until(() => health.length == 2 && acks.length == 2);
    await settle();

    expect(report, ['r1']);
    expect(health, ['h1', 'h2']);
    expect(acks, [
      ('a', 1),
      ('b', 2),
    ]);
    expect(errors, isEmpty);
  });

  test('servidor fora: insiste até voltar', () async {
    await start();
    var refusals = 3;
    rest.fake.onStream = (_) =>
        refusals-- > 0 ? const Reply.json(null, status: 503) : null;
    final seen = collect(rest.db.ref('home/menu').onValue);

    await until(() => rest.fake.liveStreams.isNotEmpty);
    await rest.fake.streams.single.put('/', 'menu');
    await until(() => seen.length == 1);

    expect(rest.fake.calls, hasLength(4));
    expect(errors, isEmpty);
  });

  test('conexão muda demais é dada por morta e reaberta', () async {
    await start(
      timings: const StreamTimings(
        watchdog: Duration(milliseconds: 80),
        minBackoff: Duration(milliseconds: 10),
        maxBackoff: Duration(milliseconds: 40),
      ),
    );
    final seen = collect(rest.db.ref('home/menu').onValue);
    final first = await opened();
    await first.put('/', 'menu');
    await until(() => seen.length == 1);

    final second = await opened(2);
    await second.put('/', 'menu 2');
    await until(() => seen.length == 2);

    expect(errors, isEmpty);
  });

  test('evento ilegível religa e ressincroniza', () async {
    await start();
    final seen = collect(rest.db.ref('home/menu').onValue);
    final first = await opened();
    await first.put('/', 'menu');
    await until(() => seen.length == 1);

    await first.send('put', 'not an object');
    final second = await opened(2);
    await second.put('/', 'menu 2');
    await until(() => seen.length == 2);

    expect(seen, ['menu', 'menu 2']);
    expect(errors, isEmpty);
  });

  group('acesso negado', () {
    test('na abertura: tenta um token novo e então entrega o erro', () async {
      await start();
      await rest.auth.idTokenOrNull();
      rest.fake.onStream = (_) =>
          const Reply.json({'error': 'Permission denied'}, status: 401);
      final seen = collect(rest.db.ref('school/members').onValue);

      await until(() => errors.isNotEmpty);
      await settle();

      expect(errors.single, denied);
      expect(seen, isEmpty);
      expect(rest.fake.accounts.refreshes, 2);
      expect(rest.fake.calls, hasLength(2));
    });

    test('token vencido na abertura não é negação', () async {
      await start();
      var first = true;
      rest.fake.onStream = (_) {
        if (!first) return null;
        first = false;
        return const Reply.json({'error': 'Auth token is expired'}, status: 401);
      };
      final seen = collect(rest.db.ref('school/members').onValue);

      await until(() => rest.fake.liveStreams.isNotEmpty);
      await rest.fake.streams.single.put('/', 'ok');
      await until(() => seen.length == 1);

      expect(errors, isEmpty);
    });

    test('no meio (cancel): todos os ouvintes da raiz recebem', () async {
      await start();
      final report = collect(rest.db.ref('devices/pc1/report').onValue);
      collect(rest.db.ref('devices/pc1/ack').onChildAdded);
      final stream = await opened();
      await stream.put('/', {'report': 'r1'});
      await until(() => report.length == 1);

      await stream.send('cancel', 'Permission denied');
      await until(() => errors.length == 2);
      await settle();

      expect(errors, everyElement(denied));
      expect(rest.fake.streams, hasLength(1));
    });

    test('ouvinte novo depois da negação tenta de novo', () async {
      await start();
      var refuse = true;
      rest.fake.onStream = (_) => refuse
          ? const Reply.json({'error': 'Permission denied'}, status: 401)
          : null;
      collect(rest.db.ref('devices/pc1/report').onValue);
      await until(() => errors.length == 1);

      refuse = false;
      final again = collect(rest.db.ref('devices/pc1/report').onValue);
      final stream = await opened();
      await stream.put('/', {'report': 'r1'});
      await until(() => again.length == 1);

      expect(again, ['r1']);
    });
  });

  test('auth_revoked religa com token novo, sem erro para quem escuta',
      () async {
    await start();
    final seen = collect(rest.db.ref('teachers/uid-1/prefs').onValue);
    final first = await opened();
    await first.put('/', 'a');
    await until(() => seen.length == 1);

    await first.send('auth_revoked', 'token expired');
    final second = await opened(2);
    await second.put('/', 'a');
    await settle();

    expect(second.request.query['auth'], isNot(first.request.query['auth']));
    expect(second.request.query['auth'], rest.fake.accounts.lastToken);
    expect(seen, ['a']);
    expect(errors, isEmpty);
  });

  test('token perto de vencer reabre o stream com o novo', () async {
    // Vigia longa: quem reabre aqui tem de ser a renovação, não o silêncio.
    await start(
      timings: const StreamTimings(
        watchdog: Duration(seconds: 20),
        minBackoff: Duration(milliseconds: 10),
        maxBackoff: Duration(milliseconds: 40),
      ),
    );
    // 301 s de validade e 300 s de margem: a renovação cai em 1 s.
    rest.fake.accounts.expiresIn = '301';
    final seen = collect(rest.db.ref('teachers/uid-1/prefs').onValue);
    final first = await opened();
    await first.put('/', 'a');
    await until(() => seen.length == 1);

    final second = await opened(2);

    expect(second.request.query['auth'], isNot(first.request.query['auth']));
    expect(errors, isEmpty);
  });

  test('trocar de conta reabre os streams com a conta nova', () async {
    await start();
    final seen = collect(rest.db.ref('school/meta').onValue);
    final first = await opened();
    await first.put('/', 'old');
    await until(() => seen.length == 1);

    rest.fake.accounts.uid = 'uid-google';
    expect(await rest.auth.linkGoogle('google-id-token'), GoogleLink.switched);
    final second = await opened(2);
    await second.put('/', 'new');
    await until(() => seen.length == 2);

    expect(second.request.query['auth'], rest.fake.accounts.lastToken);
    expect(seen, ['old', 'new']);
    await until(() => first.closed);
    expect(rest.fake.liveStreams, [second]);
  });

  test('cancelar a última escuta da raiz fecha a conexão', () async {
    await start();
    collect(rest.db.ref('devices/pc1/report').onValue);
    final health = collect(rest.db.ref('devices/pc1/health').onValue);
    final stream = await opened();
    await stream.put('/', {'report': 'r1'});
    await until(() => health.length == 1);

    await subscriptions.removeAt(0).cancel();
    await stream.put('/health', 'h1');
    await until(() => health.length == 2);
    expect(stream.closed, isFalse);

    await subscriptions.removeAt(0).cancel();
    await until(() => stream.closed);
    await settle();
    expect(rest.fake.streams, hasLength(1));
  });
}
