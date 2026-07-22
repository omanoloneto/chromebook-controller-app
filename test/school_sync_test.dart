// Núcleo do sync dos stores da escola: LWW por rev, anti-eco por hash,
// envelope cifrado com a chave da escola (sem Firebase — só a parte pura).

import 'dart:io';

import 'package:controle_de_aula/src/cloud/school_sync.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late SessionCrypto crypto;
  var relogio = 1000;

  SchoolSync sync() => SchoolSync(
        crypto: crypto,
        nowServerMs: () => relogio,
        dir: tmp,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync');
    crypto = SessionCrypto(List<int>.generate(32, (i) => i));
    relogio = 1000;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> escrever(String k, String conteudo) async {
    await File('${tmp.path}/${kStoresCompartilhados[k]!}')
        .writeAsString(conteudo);
  }

  Future<String> ler(String k) async =>
      File('${tmp.path}/${kStoresCompartilhados[k]!}').readAsString();

  test('push→aplicar: roundtrip cifrado entre dois "celulares"', () async {
    final a = sync();
    await escrever('turmas', '{"turmas":[{"nome":"5º ano"}]}');
    final payload = await a.prepararPush('turmas');
    expect(payload, isNotNull);

    // Celular B (mesmo dir simula o arquivo local dele) aplica o remoto.
    final b = sync();
    await escrever('turmas', '{"turmas":[]}'); // estado antigo do B
    final aplicou =
        await b.aplicarRemoto('turmas', payload!['rev'], payload['env']);
    expect(aplicou, true);
    expect(await ler('turmas'), '{"turmas":[{"nome":"5º ano"}]}');
  });

  test('LWW: rev igual ou mais velho não aplica', () async {
    final s = sync();
    await escrever('rules', 'v1');
    final p1 = await s.prepararPush('rules'); // rev 1000
    expect(
      await s.aplicarRemoto('rules', p1!['rev'], p1['env']),
      false,
      reason: 'eco do próprio push (mesmo rev) não reaplica',
    );
    relogio = 999; // outro celular com payload mais velho
    final velho = sync();
    await escrever('rules', 'v0');
    final p0 = await velho.prepararPush('rules');
    await escrever('rules', 'v1');
    expect(await s.aplicarRemoto('rules', p0!['rev'], p0['env']), false);
    expect(await ler('rules'), 'v1');
  });

  test('anti-eco: push sem mudança de conteúdo é suprimido', () async {
    final s = sync();
    await escrever('units', '{"a":1}');
    expect(await s.prepararPush('units'), isNotNull);
    relogio = 2000;
    expect(await s.prepararPush('units'), isNull); // conteúdo igual
    await escrever('units', '{"a":2}');
    expect(await s.prepararPush('units'), isNotNull);
  });

  test('aplicar remoto atualiza o hash: não re-pusha o que veio de fora',
      () async {
    final a = sync();
    await escrever('names', '{"d1":"Maria"}');
    final payload = await a.prepararPush('names');

    final b = sync();
    await escrever('names', '{}');
    await b.aplicarRemoto('names', payload!['rev'], payload['env']);
    relogio = 3000;
    expect(
      await b.prepararPush('names'),
      isNull,
      reason: 'conteúdo local == remoto aplicado — push seria eco',
    );
  });

  test('envelope de outra chave é ignorado (escola trocada)', () async {
    final outra = SchoolSync(
      crypto: SessionCrypto(List<int>.generate(32, (i) => 99 - i)),
      nowServerMs: () => 5000,
      dir: tmp,
    );
    await escrever('turmas', 'segredo');
    final payload = await outra.prepararPush('turmas');
    final s = sync();
    expect(
      await s.aplicarRemoto('turmas', payload!['rev'], payload['env']),
      false,
    );
  });

  test('payload inválido não aplica', () async {
    final s = sync();
    expect(await s.aplicarRemoto('turmas', 'x', 'env'), false);
    expect(await s.aplicarRemoto('turmas', 1, 42), false);
  });
}
