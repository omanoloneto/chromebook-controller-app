// Entrada do professor no computador: o QR abre um canal, o celular grava a
// conta e a chave nele, e o computador só troca de conta com uma chave íntegra.

import 'dart:async';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:controle_de_aula/src/cloud/login_handoff.dart';
import 'package:controle_de_aula/src/cloud/qr_payload.dart';
import 'package:controle_de_aula/src/pairing/computer_login.dart';
import 'package:controle_de_aula/src/secure/key_store.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:controle_de_aula/src/ui/computer_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _User implements AuthUser {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthGateway {
  _Auth(this.log);

  final List<String> log;
  Object? linkError;
  Object? anonymousError;

  @override
  AuthUser? currentUser;

  @override
  Future<AuthUser> signInAnonymously() async {
    if (anonymousError != null) throw anonymousError!;
    log.add('anonymous');
    return currentUser = _User();
  }

  @override
  Future<GoogleLink> linkGoogle(String idToken) async {
    log.add('link:$idToken');
    if (linkError != null) throw linkError!;
    return GoogleLink.switched;
  }
}

class _Snapshot implements DbSnapshot {
  _Snapshot(this.value);

  @override
  final Object? value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ref implements DbRef {
  _Ref(this.path, this.log);

  final String path;
  final List<String> log;
  late final StreamController<DbEvent> events = StreamController<DbEvent>(
    onCancel: () => log.add('cancel:$path'),
  );

  @override
  Stream<DbEvent> get onValue => events.stream;

  @override
  Future<void> remove() async => log.add('remove:$path');

  void deliver(Object? value) => events.add(DbEvent(_Snapshot(value)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Db implements RealtimeDb {
  _Db(this.log);

  final List<String> log;
  final Map<String, _Ref> refs = {};

  @override
  DbRef ref([String? path]) => refs.putIfAbsent(path!, () => _Ref(path, log));
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 2000 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

Future<String> _teacherKeys() async {
  final pair = await DeviceKeyPair.generate();
  return '${pubToB64url(await pair.privateBytes())}:${pubToB64url(pair.publicBytes)}';
}

void main() {
  late List<String> log;
  late _Auth auth;
  late _Db db;
  late List<String> saved;
  late ComputerLogin login;

  setUp(() {
    log = [];
    auth = _Auth(log);
    db = _Db(log);
    saved = [];
    login = ComputerLogin(
      auth: auth,
      db: db,
      saveKeys: (keys) async {
        log.add('save');
        saved.add(keys);
      },
    );
  });

  tearDown(() => login.dispose());

  Future<_Ref> phoneDelivers({
    required String keys,
    String idToken = 'id.tok.en',
    String teacherName = ' Ana ',
    String? schoolUid = 'uid-escola',
  }) async {
    final qr = QrLoginPayload.parse(login.qrPayload!)!;
    final ref = db.refs['handoff/${qr.channel}']!;
    ref.deliver({
      ...await LoginHandoff.montar(
        qr: qr,
        idToken: idToken,
        keys: keys,
        teacherName: teacherName,
        schoolUid: schoolUid,
      ),
      'ts': 1,
    });
    return ref;
  }

  test('abre o canal como anônimo e espera o celular', () async {
    await login.start();
    expect(login.stage, ComputerLoginStage.waiting);
    expect(login.error, isNull);
    final qr = QrLoginPayload.parse(login.qrPayload!)!;
    expect(db.refs.keys, ['handoff/${qr.channel}']);
    expect(log, ['anonymous']);
  });

  test('entrega válida: guarda a chave, entra na conta e apaga o nó', () async {
    await login.start();
    final keys = await _teacherKeys();
    final ref = await phoneDelivers(keys: keys);
    await _until(() => login.stage == ComputerLoginStage.done);
    expect(saved, [keys]);
    expect(login.teacherName, 'Ana');
    expect(login.schoolUid, 'uid-escola');
    // A escuta sai antes da troca de conta, e a chave chega antes da conta.
    expect(log, [
      'anonymous',
      'cancel:${ref.path}',
      'save',
      'link:id.tok.en',
      'remove:${ref.path}',
    ]);
  });

  test('chave que não fecha com a pública não troca a conta', () async {
    await login.start();
    final first = login.qrPayload;
    final other = await DeviceKeyPair.generate();
    final keys = (await _teacherKeys()).split(':').first;
    final ref = await phoneDelivers(keys: '$keys:${pubToB64url(other.publicBytes)}');
    await _until(() => login.error != null && login.stage == ComputerLoginStage.waiting);
    expect(login.error, kInvalidKeyText);
    expect(saved, isEmpty);
    expect(log.where((e) => e.startsWith('link:')), isEmpty);
    expect(log, contains('remove:${ref.path}'));
    expect(login.qrPayload, isNot(first));
  });

  test('conta recusada: avisa e mostra outro código', () async {
    auth.linkError = StateError('recusado');
    await login.start();
    final first = login.qrPayload;
    final ref = await phoneDelivers(keys: await _teacherKeys());
    await _until(() => login.error != null && login.stage == ComputerLoginStage.waiting);
    expect(login.error, kLoginFailedText);
    expect(log, contains('remove:${ref.path}'));
    expect(login.qrPayload, isNot(first));
  });

  test('nó vazio ou de outra chave não muda nada', () async {
    await login.start();
    final qr = QrLoginPayload.parse(login.qrPayload!)!;
    final ref = db.refs['handoff/${qr.channel}']!;
    ref.deliver(null);
    final stranger = await DeviceKeyPair.generate();
    ref.deliver(
      await LoginHandoff.montar(
        qr: QrLoginPayload(channel: qr.channel, pub: pubToB64url(stranger.publicBytes)),
        idToken: 't',
        keys: await _teacherKeys(),
        teacherName: 'Ana',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(login.stage, ComputerLoginStage.waiting);
    expect(log, ['anonymous']);
  });

  test('sem rede: falha e tenta de novo quando pedirem', () async {
    auth.anonymousError = StateError('offline');
    await login.start();
    expect(login.stage, ComputerLoginStage.failed);
    expect(login.error, kLoginFailedText);
    expect(login.qrPayload, isNull);
    auth.anonymousError = null;
    await login.start();
    expect(login.stage, ComputerLoginStage.waiting);
    expect(login.error, isNull);

    final qr = QrLoginPayload.parse(login.qrPayload!)!;
    db.refs['handoff/${qr.channel}']!.events.addError(StateError('caiu'));
    await _until(() => login.stage == ComputerLoginStage.failed);
    expect(login.error, kLoginFailedText);
  });

  test('validPair só aceita o par íntegro', () async {
    final keys = await _teacherKeys();
    expect(await KeyStore.validPair(keys), isTrue);
    expect(await KeyStore.validPair(' $keys\n'), isTrue);
    final parts = keys.split(':');
    expect(await KeyStore.validPair('${parts[1]}:${parts[0]}'), isFalse);
    expect(await KeyStore.validPair(parts[0]), isFalse);
    expect(await KeyStore.validPair('lixo:lixo'), isFalse);
    expect(await KeyStore.validPair(''), isFalse);
  });

  for (final size in const [Size(1280, 720), Size(400, 800)]) {
    testWidgets('tela de entrada em ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      login
        ..stage = ComputerLoginStage.waiting
        ..qrPayload = '{"v":1,"t":"login","c":"canal","pub":"AAAA"}';
      await tester.pumpWidget(MaterialApp(home: ComputerLoginPage(login: login)));
      expect(find.text('Entrar pelo celular'), findsOneWidget);
      expect(find.text('Aguardando o celular…'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Tentar de novo'), findsNothing);

      login
        ..stage = ComputerLoginStage.failed
        ..error = kLoginFailedText
        ..qrPayload = null;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      login.notifyListeners();
      await tester.pump();
      expect(find.text(kLoginFailedText), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
