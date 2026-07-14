// Numeração de unidades: sequência por professor, reuso no re-pareamento,
// número nunca volta ao pool.

import 'dart:io';

import 'package:controle_de_aula/src/pairing/unit_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('units');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('sequência começa em 1 e cresce na ordem de pareamento', () async {
    final store = await UnitStore.load(dir: tmp);
    expect(store.candidatoPara('a'), 1);
    await store.definir('a', 1);
    expect(store.candidatoPara('b'), 2);
    await store.definir('b', 2);
    expect(store.candidatoPara('c'), 3);
  });

  test('re-parear o mesmo device mantém o número', () async {
    final store = await UnitStore.load(dir: tmp);
    await store.definir('a', 1);
    await store.definir('b', 2);
    expect(store.candidatoPara('a'), 1);
  });

  test('candidato não persiste — pareamento falho não queima número', () async {
    final store = await UnitStore.load(dir: tmp);
    await store.definir('a', 1);
    expect(store.candidatoPara('x'), 2);
    expect(store.candidatoPara('y'), 2); // ninguém confirmou; segue 2
  });

  test('persiste e recarrega do disco', () async {
    final store = await UnitStore.load(dir: tmp);
    await store.definir('a', 1);
    await store.definir('b', 2);
    final relido = await UnitStore.load(dir: tmp);
    expect(relido.numeroDe('b'), 2);
    expect(relido.candidatoPara('novo'), 3);
  });
}
