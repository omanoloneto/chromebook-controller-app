// Ordenação natural: números dentro do nome comparados por magnitude.
// Cenário do usuário: unidades 1, 3, 12, 22 devem sair nessa ordem (não
// 1, 12, 22, 3 como no compareTo puro).

import 'package:controle_de_aula/src/util/natural_sort.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> ordenar(List<String> xs) => [...xs]..sort(compararNatural);

void main() {
  test('unidades saem em ordem numérica, não lexicográfica', () {
    expect(
      ordenar(['Unidade 1', 'Unidade 12', 'Unidade 22', 'Unidade 3']),
      ['Unidade 1', 'Unidade 3', 'Unidade 12', 'Unidade 22'],
    );
  });

  test('só números (sem prefixo) também', () {
    expect(ordenar(['1', '12', '22', '3']), ['1', '3', '12', '22']);
  });

  test('case-insensitive; texto puro = ordem alfabética normal', () {
    expect(ordenar(['zeta', 'Alfa', 'beta']), ['Alfa', 'beta', 'zeta']);
  });

  test('zeros à esquerda comparam por magnitude (007 == 7 em ordem)', () {
    expect(ordenar(['PC 007', 'PC 7', 'PC 10']), ['PC 007', 'PC 7', 'PC 10']);
    // 7 e 007 empatam por magnitude; 10 vem depois.
  });

  test('prefixo igual: string mais curta antes', () {
    expect(ordenar(['Unidade 2 sala', 'Unidade 2']), ['Unidade 2', 'Unidade 2 sala']);
  });

  test('vários grupos de dígitos', () {
    expect(
      ordenar(['sala 2 pc 10', 'sala 2 pc 2', 'sala 10 pc 1']),
      ['sala 2 pc 2', 'sala 2 pc 10', 'sala 10 pc 1'],
    );
  });
}
