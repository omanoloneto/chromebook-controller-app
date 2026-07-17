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

  test('deviceIdDoNumero acha o dono; número livre = null', () async {
    final store = await UnitStore.load(dir: tmp);
    await store.definir('a', 1);
    await store.definir('b', 2);
    expect(store.deviceIdDoNumero(2), 'b');
    expect(store.deviceIdDoNumero(9), null);
  });

  test('swap no nível do store: dois definir trocam os números', () async {
    final store = await UnitStore.load(dir: tmp);
    await store.definir('a', 2);
    await store.definir('b', 5);
    // "b vira 2": o controller grava b=2 e devolve 5 ao antigo dono.
    await store.definir('b', 2);
    await store.definir('a', 5);
    expect(store.numeroDe('b'), 2);
    expect(store.numeroDe('a'), 5);
    expect(store.proximo(), 6); // maior atribuído + 1, sem duplicar
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
