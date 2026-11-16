// Modo monitora (docs/protocolo.md §3.1): chave própria, canal mon/ e um PC de
// mentira que decifra com a chave dele, como o agente do Celita.

import 'dart:async';
import 'dart:convert';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:controle_de_aula/src/cloud/monitoras.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/pairing/monitora_controller.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:controle_de_aula/src/ui/monitora_shell.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a chave da monitora vai e volta como texto "priv:pub"', () async {
    final par = await DeviceKeyPair.generate();
    final texto = await chaveEmTexto(par);
    final volta = await chaveDoTexto(texto);
    expect(volta!.publicBytes, par.publicBytes);
    expect(pubToB64url(par.publicBytes), hasLength(43));
    expect(await chaveDoTexto('${texto.split(':')[0]}:outra'), isNull);
    expect(await chaveDoTexto('lixo'), isNull);
    expect(await chaveDoTexto(null), isNull);
  });

  test('liberar cria a chave uma vez só e lista o e-mail', () async {
    final banco = _Banco();
    final m = SchoolMonitoras(database: banco);
    expect(await m.adicionar('Ana.Lima@Escola.com'), isNull);
    final chave = banco.ler('school/monitorKey/keys');
    expect(chave, isA<String>());
    expect(await m.adicionar('bia@escola.com'), isNull);
    expect(banco.ler('school/monitorKey/keys'), chave);
    expect(banco.ler('school/monitores'), {'ana,lima@escola,com': true, 'bia@escola,com': true});
    expect(await m.adicionar('não é e-mail'), isNotNull);
  });

  test('o professor publica a pub só nos PCs da escola que não a têm', () async {
    final banco = _Banco();
    final m = SchoolMonitoras(database: banco);
    expect(await m.publicarNosPcs(), 0, reason: 'sem monitora, nada a publicar');
    final par = await m.garantirChave();
    final pub = pubToB64url(par.publicBytes);
    banco
      ..gravar('school/devices', {'pc1': true, 'pc2': true, 'pc3': false})
      ..gravar('devices/pc2/mon/pub', pub);
    expect(await m.publicarNosPcs(), 1);
    expect(banco.ler('devices/pc1/mon/pub'), pub);
    expect(banco.ler('devices/pc3/mon/pub'), isNull);
  });

  group('controller', () {
    late _Banco banco;
    late _PcDeMentira pc;
    late MonitoraController c;

    setUp(() async {
      banco = _Banco();
      final chave = await SchoolMonitoras(database: banco).garantirChave();
      pc = await _PcDeMentira.criar(banco, 'pc1', chave);
      banco.gravar('school/devices', {'pc1': true});
      await pc.publicarCarga(level: 23, plugged: false, session: true);
      c = MonitoraController(database: banco, espera: const Duration(milliseconds: 300));
      await c.start();
      await _ate(() => c.pcs.isNotEmpty && c.pcs.first.bateria != null);
    });

    tearDown(() async {
      await c.stop();
      await pc.parar();
    });

    test('lista o PC com número, bateria e conta aberta', () {
      final lido = c.pcs.single;
      expect(c.estado, EstadoMonitora.pronto);
      expect(lido.titulo, 'Unidade 7');
      expect((lido.bateria, lido.naTomada, lido.contaAberta), (23, false, true));
      expect(c.ligado(lido), isTrue);
    });

    test('desligar vai pelo mon/cmd com a chave da monitora', () async {
      final r = await c.energia(c.pcs.single, AcaoEnergia.desligar);
      expect(r.ok, isTrue);
      expect(pc.recebidos.single['type'], MessageType.energia);
      expect(pc.recebidos.single['payload'], {'acao': 'desligar'});
      expect(banco.ler('devices/pc1/cmd'), isNull, reason: 'nunca na fila do professor');
      expect(banco.ler('devices/pc1/mon/ack'), isNull, reason: 'a monitora apaga o ack lido');
    });

    test('ver tela abre o mon/snapshot e apaga', () async {
      final r = await c.verTela(c.pcs.single);
      expect(utf8.decode(r.jpeg!), 'jpeg');
      expect(banco.ler('devices/pc1/mon/snapshot'), isNull);
    });

    test('recusa do PC vira texto de monitora', () async {
      pc.recusar = true;
      final r = await c.mensagem(c.pcs.single, 'oi');
      expect((r.ok, r.erro), (false, 'nao_permitido'));
    });

    test('PC que não responde dá sem_resposta e o pedido some da fila', () async {
      pc.mudo = true;
      final r = await c.fecharAbas(c.pcs.single);
      expect(r.erro, 'sem_resposta');
      expect(banco.ler('devices/pc1/mon/cmd'), isNull);
    });
  });

  testWidgets('Sala e Carrinho mostram a unidade sem nada do professor', (tester) async {
    final c = await tester.runAsync(() async {
      final banco = _Banco();
      final chave = await SchoolMonitoras(database: banco).garantirChave();
      final pc = await _PcDeMentira.criar(banco, 'pc1', chave);
      banco.gravar('school/devices', {'pc1': true});
      await pc.publicarCarga(level: 15, plugged: false, session: false);
      final c = MonitoraController(database: banco);
      await c.start();
      await _ate(() => c.pcs.isNotEmpty && c.pcs.first.bateria != null);
      return c;
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MonitoraShell(controller: c!, onSair: () async {})));
    await tester.pump();
    expect(find.text('Unidade 7'), findsOneWidget);
    expect(find.text('Desligar todos'), findsOneWidget);
    for (final proibido in ['Câmera', 'Foto', 'Liberar sites', 'Diagnóstico', 'Atualizar']) {
      expect(find.textContaining(proibido), findsNothing, reason: proibido);
    }
    await tester.tap(find.text('Carrinho'));
    await tester.pump();
    expect(find.text('Fora da tomada'), findsOneWidget);
    expect(find.text('1 com bateria baixa'), findsOneWidget);
    await tester.runAsync(c.stop);
  });

  test('sem a chave da monitora (acesso negado) o app diz sem acesso', () async {
    final banco = _Banco()..negados.add('school/monitorKey/keys');
    final c = MonitoraController(database: banco);
    await c.start();
    expect(c.estado, EstadoMonitora.semAcesso);
    await c.stop();
  });
}

Future<void> _ate(bool Function() condicao) async {
  final limite = DateTime.now().add(const Duration(seconds: 3));
  while (!condicao()) {
    if (DateTime.now().isAfter(limite)) throw TimeoutException('condição');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

// O agente do Celita em miniatura: decifra mon/cmd com a chave do PC e a pub
// da monitora, responde no mon/ack e põe a tela no mon/snapshot.
class _PcDeMentira {
  _PcDeMentira._(this.banco, this.id, this.cripto);

  final _Banco banco;
  final String id;
  final SessionCrypto cripto;
  final List<Map<String, dynamic>> recebidos = [];
  bool recusar = false;
  bool mudo = false;
  int _seq = 0;
  StreamSubscription<DbEvent>? _fila;

  static Future<_PcDeMentira> criar(_Banco banco, String id, DeviceKeyPair monitora) async {
    final proprio = await DeviceKeyPair.generate();
    final cripto = SessionCrypto(await proprio.deriveSessionKey(monitora.publicBytes));
    banco
      ..gravar('devices/$id/meta', {'label': 'celita-u7', 'pub': pubToB64url(proprio.publicBytes)})
      ..gravar('devices/$id/bind/numero', 7)
      ..gravar('devices/$id/presence/lastSeen', DateTime.now().millisecondsSinceEpoch);
    final pc = _PcDeMentira._(banco, id, cripto);
    pc._fila = banco.ref('devices/$id/mon/cmd').onValue.listen((e) => pc._atender(e.snapshot.value));
    return pc;
  }

  Future<String> _selar(Map<String, dynamic> obj) =>
      cripto.seal({'sid': 1, 'seq': ++_seq, 'ts': DateTime.now().millisecondsSinceEpoch, 'v': 1, ...obj});

  Future<void> publicarCarga({required int level, required bool plugged, required bool session}) async =>
      banco.gravar('devices/$id/mon/carga', {
        'env': await _selar({'type': MessageType.cargaReport, 'level': level, 'plugged': plugged, 'session': session}),
        'ts': 1,
      });

  Future<void> _atender(Object? fila) async {
    if (fila is! Map || mudo) return;
    for (final entry in fila.entries.toList()) {
      final msg = await cripto.open(entry.value as String);
      banco.gravar('devices/$id/mon/cmd/${entry.key}', null);
      recebidos.add(msg);
      if (msg['type'] == MessageType.captureScreen && !recusar) {
        banco.gravar('devices/$id/mon/snapshot', {
          'env': await _selar({'type': MessageType.screenSnapshot, 'id': msg['id'], 'jpegB64': base64.encode(utf8.encode('jpeg'))}),
          'ts': 1,
        });
      }
      banco.gravar(
        'devices/$id/mon/ack/${entry.key}',
        await _selar({
          'type': MessageType.ack,
          'id': msg['id'],
          'ok': !recusar,
          'error': recusar ? 'nao_permitido' : null,
        }),
      );
    }
  }

  Future<void> parar() async => _fila?.cancel();
}

// RTDB em memória: onValue, get, set, push e remove.
class _Banco implements RealtimeDb {
  final Map<String, Object?> _raiz = {};
  final Map<String, List<StreamController<DbEvent>>> _ouvintes = {};
  final Set<String> negados = {};
  int _push = 0;

  @override
  DbRef ref([String? path]) => _Ref(this, path ?? '');

  Object? ler(String caminho) {
    Object? no = _raiz;
    for (final p in caminho.split('/')) {
      no = no is Map ? no[p] : null;
    }
    return no is Map && no.isEmpty ? null : _copia(no);
  }

  void gravar(String caminho, Object? valor) {
    final partes = caminho.split('/');
    var no = _raiz;
    for (final p in partes.take(partes.length - 1)) {
      no = (no[p] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    valor == null ? no.remove(partes.last) : no[partes.last] = _copia(valor);
    for (final MapEntry(key: ouvido, value: lista) in _ouvintes.entries.toList()) {
      if (ouvido == caminho || ouvido.startsWith('$caminho/') || caminho.startsWith('$ouvido/')) {
        for (final c in lista.toList()) {
          c.add(DbEvent(_Foto(ler(ouvido))));
        }
      }
    }
  }

  void _negar(String caminho) {
    if (negados.contains(caminho)) {
      throw FirebaseException(plugin: 'firebase_database', code: 'permission-denied');
    }
  }

  Stream<DbEvent> ouvir(String caminho) {
    late final StreamController<DbEvent> c;
    c = StreamController(
      onListen: () {
        _ouvintes.putIfAbsent(caminho, () => []).add(c);
        c.add(DbEvent(_Foto(ler(caminho))));
      },
      onCancel: () async => _ouvintes[caminho]?.remove(c),
    );
    return c.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Object? _copia(Object? v) =>
    v is Map ? <String, Object?>{for (final e in v.entries) '${e.key}': _copia(e.value)} : v;

class _Ref implements DbRef {
  _Ref(this._banco, this._caminho);

  final _Banco _banco;
  final String _caminho;

  @override
  String? get key => _caminho.split('/').last;

  @override
  DbRef child(String path) => _Ref(_banco, '$_caminho/$path');

  @override
  DbRef push() => _Ref(_banco, '$_caminho/-p${(_banco._push++).toString().padLeft(4, '0')}');

  @override
  Stream<DbEvent> get onValue => _banco.ouvir(_caminho);

  @override
  Future<DbSnapshot> get() async {
    _banco._negar(_caminho);
    return _Foto(_banco.ler(_caminho));
  }

  @override
  Future<void> set(Object? value) async => _banco.gravar(_caminho, value);

  @override
  Future<void> remove() => set(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Foto implements DbSnapshot {
  _Foto(this.value);

  @override
  final Object? value;

  @override
  bool get exists => value != null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
