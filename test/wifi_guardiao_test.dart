// Guardião do Wi-Fi da escola (docs/protocolo.md §9): vetor fixo igual ao do
// agente do Celita (test_wifi_escola.py, VetorTest), com as chaves de
// keypair_test.dart (A é o celular, B o PC); o guardião num RTDB em memória;
// e o par dele nunca entra em backup.

import 'dart:async';
import 'dart:io';

import 'package:controle_de_aula/src/cloud/backup_store.dart';
import 'package:controle_de_aula/src/cloud/wifi_guardiao.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/secure/key_store.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:controle_de_aula/src/secure/wifi_crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

const aD = 'kLHtc7YxBsgOOgdkfgd50vy_eGvUACVycVkOsUiQX3Q';
const aX = 'Z03jzVY4eGibMJbdDlyaM-hjbo7agkCE7LSiORqfChM';
const bD = 'WLMjlWRflQMiHmzsgnJ1jfWuJOHhqyBy0YS4x0dnbmQ';
const bX = 'JS-rAkqU_z8Q6eeqM32bnG47qUM0a2Iuatbgo_-24GQ';
const kcvDoAgente = 'A7Sy0VYvsKfBTSAvvBn0C3DgdXRqmvGR3nlnwlOA_GU';
const embrulhoDoAgente = 'jJvNeEFG2x90SQv0uaPe7GxMvmhTBw5RvMkQWxuoJ1E';
const envDoAgente =
    'AAAAAAAAAAAAAAAAMiE1MenGpa1JZJTyU+wXI0C0PxP1UqTKtLHVjQCbD1x/McG8'
    'GodX/WAVgkXPh71M8YGv3EQOigVKykGVW4J1BiLMOP0DSOGtBQ==';
// Entrega que selarEntrega gerou e o agente abre com B (VetorTest).
const entregaPub = '00ui1u9fEDS_g6X3CfZsR_B3fSzXMgVgCtcU04S-0R4';
const entregaEnv =
    'ZKwK9NREJQpikMztMdILjt2wrVALXZjPkzdNIZvSU5XM0Bzm9HLY1WifWeVQdV1xmhk'
    'MIXtyAxkd0/Oprgx30J/lTyE9uBVcbIsQOs9sfgUj93gbZw==';

void main() {
  final frota = List<int>.generate(32, (i) => i);
  final conteudo = {'v': 1, 'k': SessionCrypto.keyToBase64url(frota)};

  Future<DeviceKeyPair> celular() =>
      DeviceKeyPair.fromBytes(pubFromB64url(aD), pubFromB64url(aX));
  Future<DeviceKeyPair> pc() =>
      DeviceKeyPair.fromBytes(pubFromB64url(bD), pubFromB64url(bX));

  // O lado do PC (wifi._abrir_selada no agente).
  Future<Map<String, dynamic>> pcAbre(String pub, String env) async =>
      SessionCrypto(await (await pc()).deriveWifiWrapKey(pubFromB64url(pub)))
          .open(env);

  // O PC sela para o guardião (distribuir no agente).
  Future<String> pcSela(String pubDoGuardiao) async => SessionCrypto(
        await (await pc()).deriveWifiWrapKey(pubFromB64url(pubDoGuardiao)),
      ).seal(conteudo);

  test('kcv e embrulho iguais aos do agente', () async {
    expect(await kcvDaChave(frota), kcvDoAgente);
    final a = await celular();
    final b = await pc();
    expect(
      pubToB64url(await a.deriveWifiWrapKey(pubFromB64url(bX))),
      embrulhoDoAgente,
    );
    expect(
      pubToB64url(await b.deriveWifiWrapKey(pubFromB64url(aX))),
      embrulhoDoAgente,
    );
  });

  test('sela igual ao agente e abre a chave que o PC selou', () async {
    final embrulho = await (await celular()).deriveWifiWrapKey(pubFromB64url(bX));
    expect(
      await SessionCrypto(embrulho).seal(conteudo, nonce: List.filled(12, 0)),
      envDoAgente,
    );
    expect(
      await abrirChaveDaFrota(
        guardiao: await celular(),
        pubDoPc: bX,
        env: envDoAgente,
        kcv: kcvDoAgente,
      ),
      frota,
    );
  });

  test('recusa a chave que não é a da escola ou que não veio daquele PC',
      () async {
    final a = await celular();
    Future<List<int>?> abrir({
      String pubDoPc = bX,
      String env = envDoAgente,
      String kcv = kcvDoAgente,
    }) =>
        abrirChaveDaFrota(guardiao: a, pubDoPc: pubDoPc, env: env, kcv: kcv);

    expect(await abrir(kcv: embrulhoDoAgente), isNull, reason: 'kcv de outra');
    expect(await abrir(pubDoPc: aX), isNull, reason: 'pública de outro PC');
    expect(await abrir(pubDoPc: 'curta'), isNull);
    expect(await abrir(env: 'AAAA'), isNull);
    final embrulho = await a.deriveWifiWrapKey(pubFromB64url(bX));
    final outraVersao = await SessionCrypto(embrulho)
        .seal({'v': 2, 'k': SessionCrypto.keyToBase64url(frota)});
    expect(await abrir(env: outraVersao), isNull);
  });

  test('a entrega do vetor abre do lado do PC', () async {
    expect(await pcAbre(entregaPub, entregaEnv), conteudo);
  });

  test('cada entrega tem um par efêmero novo, e o PC abre', () async {
    final uma = await selarEntrega(frota, bX);
    final outra = await selarEntrega(frota, bX);
    for (final e in [uma, outra]) {
      expect(e.keys, ['pub', 'env', 'kcv']);
      expect(e['pub'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(e['kcv'], kcvDoAgente);
      expect(await pcAbre(e['pub']!, e['env']!), conteudo);
    }
    expect(outra['pub'], isNot(uma['pub']));
  });

  test('não sela para pública de ordem baixa, como o agente', () async {
    for (final u in [List.filled(32, 0), [1, ...List.filled(31, 0)]]) {
      await expectLater(
        selarEntrega(frota, pubToB64url(u)),
        throwsArgumentError,
      );
    }
  });

  test('alvos: PC do roster que publicou a pública e ainda sem a minha entrega '
      'da chave de agora', () {
    expect(
      alvosDaEntrega(
        pubs: {
          'd2': 'P2',
          'd1': 'P1',
          'd3': 'P3',
          'd5': 'P5',
          'd6': 'P6',
          'd7': 'P7',
          'd8': 'P8',
          'cb': 7,
        },
        roster: {
          'd1': true,
          'd2': true,
          'd4': true,
          'd5': false,
          'd6': true,
          'd7': true,
          'd8': true,
          'cb': true,
        },
        entregas: {
          'd1': {
            'uid-x': {'pub': 'E', 'env': 'x', 'kcv': 'K'},
          },
          'd2': {
            'uid-outro': {'pub': 'E', 'env': 'x', 'kcv': 'K'},
          },
          'd7': {
            'uid-x': {'pub': 'E', 'env': 'x', 'kcv': 'de antes do recomeço'},
          },
          'd8': {
            'uid-x': {'pub': 'E', 'env': 'x'},
          },
        },
        uid: 'uid-x',
        kcv: 'K',
      ),
      ['d2', 'd6', 'd7', 'd8'],
    );
    expect(
      alvosDaEntrega(
        pubs: {'d1': 'P1'},
        roster: {'d1': true},
        entregas: null,
        uid: 'u',
        kcv: 'K',
      ),
      ['d1'],
    );
    expect(
      alvosDaEntrega(
        pubs: null,
        roster: {'d1': true},
        entregas: null,
        uid: 'u',
        kcv: 'K',
      ),
      isEmpty,
    );
    expect(
      alvosDaEntrega(
        pubs: {'d1': 'P1'},
        roster: null,
        entregas: null,
        uid: 'u',
        kcv: 'K',
      ),
      isEmpty,
    );
  });

  test('o par do guardião ilegível ou torto se refaz sozinho', () async {
    final dir = await Directory.systemTemp.createTemp('guardiao');
    addTearDown(() => dir.delete(recursive: true));
    final arquivo = File('${dir.path}/${KeyStore.arquivoGuardiao}');
    final primeiro = await KeyStore.loadOrCreateGuardiao(dir: dir);
    expect(
      (await KeyStore.loadOrCreateGuardiao(dir: dir)).publicBytes,
      primeiro.publicBytes,
    );
    // Gravação cortada no meio, pública truncada e pública de outro par.
    for (final torto in ['abc:@@', '$aD:xw', '$aD:$bX']) {
      arquivo.writeAsStringSync(torto);
      final par = await KeyStore.loadOrCreateGuardiao(dir: dir);
      expect(par.publicBytes, hasLength(32), reason: torto);
      expect(
        (await KeyStore.loadOrCreateGuardiao(dir: dir)).publicBytes,
        par.publicBytes,
        reason: '$torto: o par novo ficou gravado',
      );
    }
  });

  test('o par do guardião nunca entra em backup', () {
    expect(KeyStore.arquivoGuardiao, 'wifi_guardiao.txt');
    expect(kArquivosDeBackup, isNot(contains(KeyStore.arquivoGuardiao)));
    final exclui = RegExp.escape(
      '<exclude domain="file" path="${KeyStore.arquivoGuardiao}" />',
    );
    final antigo = File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsStringSync();
    final novo = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    expect(
      RegExp('<full-backup-content>\\s*$exclui').hasMatch(antigo),
      isTrue,
    );
    expect(RegExp('<cloud-backup>\\s*$exclui').hasMatch(novo), isTrue);
    expect(RegExp('<device-transfer>\\s*$exclui').hasMatch(novo), isTrue);
    final manifesto =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifesto,
      contains('android:fullBackupContent="@xml/backup_rules"'),
    );
    expect(
      manifesto,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  group('no banco', () {
    const meu = 'school/wifi/guardioes/uid-x';
    const espera = Duration(seconds: 3);

    testWidgets('cadastra, abre a chave do PC, entrega a cada PC e larga a '
        'chave quando o kcv muda', (tester) async {
      final d2 = await DeviceKeyPair.generate();
      final banco = _Banco()
        ..gravar('school', {
          'devices': {'d0': true, 'd1': true, 'd2': true, 'd3': true, 'd9': true},
          'wifi': {
            'meta': {'de': 'd1', 'ts': 1, 'kcv': kcvDoAgente},
            'pubs': {
              'd0': 'torta',
              'd1': bX,
              'd2': pubToB64url(d2.publicBytes),
              'd3': 'P3',
            },
            // Celular trocado: o nó ainda tem o par antigo e a chave dele.
            'guardioes': {
              'uid-x': {
                'pub': bX,
                'ts': 1,
                'chave': {'de': 'd1', 'env': 'x'},
              },
            },
            'entregas': {
              'd3': {
                'uid-x': {
                  'pub': entregaPub,
                  'env': entregaEnv,
                  'kcv': kcvDoAgente,
                },
              },
              // A minha de antes de um recomeço: vale refazer.
              'd2': {
                'uid-x': {
                  'pub': entregaPub,
                  'env': entregaEnv,
                  'kcv': embrulhoDoAgente,
                },
              },
            },
            'redes': {
              'r1': {'env': 'x', 'ts': 1},
            },
            'chaves': {
              'd2': {'de': 'd1', 'env': 'x'},
            },
          },
        })
        ..escritas.clear();
      final guardiao =
          WifiGuardiao(uid: 'uid-x', chave: await celular(), database: banco)
            ..start();

      await tester.pump(espera);
      expect(banco.ler(meu), {
        'pub': aX,
        'ts': {'.sv': 'timestamp'},
      });
      expect(banco.escritas, [meu]);

      // Um PC da escola sela a chave para o guardião (o env do vetor).
      banco.gravar('$meu/chave', {'de': 'd1', 'env': envDoAgente});
      banco.escritas.clear();
      await tester.pump(espera);
      expect(
        banco.escritas,
        ['school/wifi/entregas/d1/uid-x', 'school/wifi/entregas/d2/uid-x'],
        reason: 'd0 tem pública torta, d3 já tem, a de d2 era de outra chave '
            'e d9 não publicou',
      );
      final d1 = banco.ler('school/wifi/entregas/d1/uid-x') as Map;
      expect(await pcAbre(d1['pub'] as String, d1['env'] as String), conteudo);
      final paraD2 = banco.ler('school/wifi/entregas/d2/uid-x') as Map;
      expect(paraD2['kcv'], kcvDoAgente);
      expect(
        await SessionCrypto(
          await d2.deriveWifiWrapKey(pubFromB64url(paraD2['pub'] as String)),
        ).open(paraD2['env'] as String),
        conteudo,
      );

      // kcv de outra chave: a guardada sai e ninguém recebe a velha.
      banco
        ..gravar('school/devices/d4', true)
        ..gravar('school/wifi/pubs/d4', bX)
        ..gravar('school/wifi/meta/kcv', embrulhoDoAgente)
        ..escritas.clear();
      await tester.pump(espera);
      expect(banco.escritas, ['$meu/chave']);
      expect(banco.ler(meu), {
        'pub': aX,
        'ts': {'.sv': 'timestamp'},
      });

      expect(
        banco.ouvidos.toSet(),
        {
          'school/wifi/meta/kcv',
          meu,
          'school/wifi/pubs',
          'school/wifi/entregas',
          'school/devices',
        },
        reason: 'nunca lê redes nem chaves',
      );
      await guardiao.stop();
      expect(banco.ouvindo, 0);
    });

    testWidgets('kcv que muda no meio das entregas: a chave velha não vai '
        'para mais ninguém', (tester) async {
      final d2 = await DeviceKeyPair.generate();
      final banco = _Banco()
        ..gravar('school', {
          'devices': {'d1': true, 'd2': true},
          'wifi': {
            'meta': {'de': 'd1', 'ts': 1, 'kcv': kcvDoAgente},
            'pubs': {'d1': bX, 'd2': pubToB64url(d2.publicBytes)},
            'guardioes': {
              'uid-x': {
                'pub': aX,
                'ts': 1,
                'chave': {'de': 'd1', 'env': envDoAgente},
              },
            },
          },
        });
      // Recomeço logo depois da primeira entrega, com a rodada em andamento.
      banco.aoGravar = (caminho) {
        if (caminho != 'school/wifi/entregas/d1/uid-x') return;
        banco
          ..aoGravar = null
          ..gravar('school/wifi/meta/kcv', 'B' * 43);
      };
      final guardiao =
          WifiGuardiao(uid: 'uid-x', chave: await celular(), database: banco)
            ..start();
      await tester.pump(espera);
      await tester.pump(espera);
      expect(banco.ler('school/wifi/entregas/d1/uid-x'), isNotNull);
      expect(banco.ler('school/wifi/entregas/d2/uid-x'), isNull);
      await guardiao.stop();
    });

    testWidgets('mesma conta em dois aparelhos abertos juntos: um só fica de '
        'guardião e entrega', (tester) async {
      final banco = _Banco()
        ..gravar('school', {
          'devices': {'d1': true},
          'wifi': {
            'meta': {'de': 'd1', 'ts': 1, 'kcv': kcvDoAgente},
            'pubs': {'d1': bX},
          },
        })
        ..escritas.clear();
      final um =
          WifiGuardiao(uid: 'uid-x', chave: await celular(), database: banco)
            ..start();
      final outro = WifiGuardiao(
        uid: 'uid-x',
        chave: await DeviceKeyPair.generate(),
        database: banco,
      )..start();

      await tester.pump(const Duration(seconds: 20));
      // Um PC da escola sela para a pública que ficou no nó.
      final pub = (banco.ler(meu) as Map)['pub'] as String;
      banco.gravar('$meu/chave', {'de': 'd1', 'env': await pcSela(pub)});
      await tester.pump(const Duration(seconds: 40));
      expect(
        banco.escritas.where((c) => c == meu).length,
        lessThanOrEqualTo(2),
      );
      final d1 = banco.ler('school/wifi/entregas/d1/uid-x') as Map;
      expect(await pcAbre(d1['pub'] as String, d1['env'] as String), conteudo);
      await um.stop();
      await outro.stop();
    });

    testWidgets('o aparelho que já era guardião cede ao que abriu depois',
        (tester) async {
      final banco = _Banco()
        ..gravar('school', {
          'devices': {'d1': true},
          'wifi': {
            'meta': {'de': 'd1', 'ts': 1, 'kcv': kcvDoAgente},
            'pubs': {'d1': bX},
            'guardioes': {
              'uid-x': {'pub': aX, 'ts': 1},
            },
          },
        })
        ..escritas.clear();
      final antigo =
          WifiGuardiao(uid: 'uid-x', chave: await celular(), database: banco)
            ..start();
      await tester.pump(espera);
      final par = await DeviceKeyPair.generate();
      final novo = WifiGuardiao(uid: 'uid-x', chave: par, database: banco)
        ..start();
      await tester.pump(const Duration(minutes: 1));
      expect(banco.escritas, [meu]);
      expect((banco.ler(meu) as Map)['pub'], pubToB64url(par.publicBytes));
      await antigo.stop();
      await novo.stop();
    });

    testWidgets('rules antigas: permission-denied e o guardião para calado',
        (tester) async {
      final banco = _Banco()
        ..gravar('school/devices/d1', true)
        ..negados.addAll([
          'school/wifi/meta/kcv',
          meu,
          'school/wifi/pubs',
          'school/wifi/entregas',
        ])
        ..escritas.clear();
      WifiGuardiao(uid: 'uid-x', chave: await celular(), database: banco)
          .start();
      await tester.pump(espera);
      expect(banco.escritas, isEmpty);
      expect(banco.ouvindo, 0);
    });
  });
}

// RTDB em memória, só o que o guardião usa: onValue, set e remove.
class _Banco implements FirebaseDatabase {
  final Map<String, Object?> _raiz = {};
  final Map<String, List<StreamController<DatabaseEvent>>> _ouvintes = {};
  final Set<String> negados = {};
  final List<String> ouvidos = [];
  final List<String> escritas = [];
  void Function(String caminho)? aoGravar;

  int get ouvindo => _ouvintes.values.fold(0, (n, l) => n + l.length);

  @override
  DatabaseReference ref([String? path]) => _Ref(this, path ?? '');

  Object? ler(String caminho) {
    Object? no = _raiz;
    for (final p in caminho.split('/')) {
      no = no is Map ? no[p] : null;
    }
    return no is Map && no.isEmpty ? null : _copia(no);
  }

  void gravar(String caminho, Object? valor) {
    escritas.add(caminho);
    final partes = caminho.split('/');
    var no = _raiz;
    for (final p in partes.take(partes.length - 1)) {
      no = (no[p] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    valor == null ? no.remove(partes.last) : no[partes.last] = _copia(valor);
    for (final MapEntry(key: ouvido, value: lista) in _ouvintes.entries) {
      if (ouvido == caminho ||
          ouvido.startsWith('$caminho/') ||
          caminho.startsWith('$ouvido/')) {
        for (final c in lista) {
          c.add(_Evento(ler(ouvido)));
        }
      }
    }
    aoGravar?.call(caminho);
  }

  Stream<DatabaseEvent> ouvir(String caminho) {
    ouvidos.add(caminho);
    late final StreamController<DatabaseEvent> c;
    c = StreamController(
      onListen: () {
        if (negados.contains(caminho)) {
          c.addError(
            FirebaseException(
              plugin: 'firebase_database',
              code: 'permission-denied',
            ),
          );
          return;
        }
        _ouvintes.putIfAbsent(caminho, () => []).add(c);
        c.add(_Evento(ler(caminho)));
      },
      // Future da zona do teste: o cancel não escapa do tempo falso.
      onCancel: () async => _ouvintes[caminho]?.remove(c),
    );
    return c.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Object? _copia(Object? v) => v is Map
    ? <String, Object?>{for (final e in v.entries) '${e.key}': _copia(e.value)}
    : v;

class _Ref implements DatabaseReference {
  _Ref(this._banco, this._caminho);

  final _Banco _banco;
  final String _caminho;

  @override
  DatabaseReference child(String path) => _Ref(_banco, '$_caminho/$path');

  @override
  Stream<DatabaseEvent> get onValue => _banco.ouvir(_caminho);

  @override
  Future<void> set(Object? value) async => _banco.gravar(_caminho, value);

  @override
  Future<void> remove() => set(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Evento implements DatabaseEvent {
  _Evento(Object? valor) : snapshot = _Foto(valor);

  @override
  final DataSnapshot snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Foto implements DataSnapshot {
  _Foto(this.value);

  @override
  final Object? value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
