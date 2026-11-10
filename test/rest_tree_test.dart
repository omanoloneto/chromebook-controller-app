// Árvore em memória do adaptador REST: as regras de dados do Realtime
// Database que o SDK aplicava e que no Linux passam a ser do app.

import 'dart:math';

import 'package:controle_de_aula/src/backend/rest/rest_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splitPath ignora barras sobrando', () {
    expect(splitPath(null), isEmpty);
    expect(splitPath('/'), isEmpty);
    expect(splitPath('/devices//pc1/'), ['devices', 'pc1']);
  });

  test('compareKeys põe inteiros antes, em ordem numérica', () {
    final keys = ['b', '10', '9', 'a', '-1', '01', '0', '4294967296']
      ..sort(compareKeys);
    expect(keys, ['-1', '0', '9', '10', '01', '4294967296', 'a', 'b']);
  });

  test('normalize troca lista por mapa e some com o que é vazio', () {
    expect(
      normalize({
        'list': ['a', null, 'c'],
        'empty': <String, Object?>{},
        'gone': null,
        'deep': {
          'only': {'nothing': null},
        },
        'leaf': 1,
      }),
      {
        'list': {'0': 'a', '2': 'c'},
        'leaf': 1,
      },
    );
    expect(normalize(<Object?>[]), isNull);
    expect(normalize('x'), 'x');
  });

  group('withValueAt', () {
    test('escreve fundo sem tocar na árvore de antes', () {
      final before = {
        'a': {'b': 1},
        'z': {'k': true},
      };
      final after = withValueAt(before, ['a', 'c', 'd'], 2);
      expect(after, {
        'a': {
          'b': 1,
          'c': {'d': 2},
        },
        'z': {'k': true},
      });
      expect(before['a'], {'b': 1});
      expect(identical((after as Map)['z'], before['z']), isTrue);
    });

    test('null apaga e poda os pais que ficaram vazios', () {
      final tree = {
        'a': {
          'b': {'c': 1},
        },
        'z': 1,
      };
      expect(withValueAt(tree, ['a', 'b', 'c'], null), {'z': 1});
      expect(withValueAt({'a': 1}, ['a'], null), isNull);
    });

    test('apagar o que não existe devolve a mesma árvore', () {
      final tree = {'a': 1};
      expect(identical(withValueAt(tree, ['x', 'y'], null), tree), isTrue);
    });

    test('escrever abaixo de uma folha troca a folha por nó', () {
      expect(withValueAt({'a': 1}, ['a', 'b'], 2), {
        'a': {'b': 2},
      });
    });
  });

  test('valueAt lê o caminho e devolve null fora dele', () {
    final tree = {
      'a': {'b': 1},
    };
    expect(valueAt(tree, ['a', 'b']), 1);
    expect(valueAt(tree, []), tree);
    expect(valueAt(tree, ['a', 'b', 'c']), isNull);
    expect(valueAt(null, ['a']), isNull);
  });

  test('sameTree compara por conteúdo', () {
    expect(
      sameTree(
        {
          'a': {'b': 1},
        },
        {
          'a': {'b': 1},
        },
      ),
      isTrue,
    );
    expect(sameTree({'a': 1}, {'a': 2}), isFalse);
    expect(sameTree({'a': 1}, {'b': 1}), isFalse);
    expect(sameTree({'a': 1}, 1), isFalse);
    expect(sameTree(null, null), isTrue);
  });

  group('export', () {
    test('mapa denso de índices vira lista, como no SDK', () {
      expect(export({'0': 'a', '1': 'b'}), ['a', 'b']);
      expect(export({'0': 'a', '2': 'c'}), ['a', null, 'c']);
    });

    test('mapa esparso ou com chave de texto continua mapa', () {
      expect(export({'5': 'a'}), {'5': 'a'});
      expect(export({'0': 'a', 'x': 'b'}), {'0': 'a', 'x': 'b'});
      expect(export({'01': 'a'}), {'01': 'a'});
    });

    test('chaves saem na ordem do banco', () {
      final value = export({'b': 1, '10': 2, 'a': 3, '9': 4}) as Map;
      expect(value.keys, ['9', '10', 'a', 'b']);
    });
  });

  group('RestSnapshot', () {
    test('filhos de mapa trazem chave e valor', () {
      final snapshot = RestSnapshot.fromJson('up', {
        'b': {'x': 1},
        'a': 'y',
      });
      expect(snapshot.key, 'up');
      expect(snapshot.exists, isTrue);
      expect(snapshot.children.map((c) => c.key), ['a', 'b']);
      expect(snapshot.children.last.value, {'x': 1});
    });

    test('filhos de lista pulam os buracos', () {
      final snapshot = RestSnapshot.fromJson('n', ['a', null, 'c']);
      expect(snapshot.children.map((c) => c.key), ['0', '2']);
    });

    test('nó vazio não existe e não tem filhos', () {
      final snapshot = RestSnapshot.fromJson('n', <String, Object?>{});
      expect(snapshot.exists, isFalse);
      expect(snapshot.value, isNull);
      expect(snapshot.children, isEmpty);
    });
  });

  group('PushIds', () {
    test('20 caracteres, e a hora manda na ordem', () {
      final ids = PushIds(Random(1));
      final early = ids.next(1794269619000);
      final late = ids.next(1794269619001);
      expect(early, hasLength(20));
      expect(early.compareTo(late), lessThan(0));
      expect(early.substring(0, 8), isNot(late.substring(0, 8)));
    });

    test('no mesmo milissegundo não repete e continua crescendo', () {
      final ids = PushIds(Random(1));
      final all = [for (var i = 0; i < 200; i++) ids.next(1794269619000)];
      expect(all.toSet(), hasLength(200));
      expect(all, [...all]..sort());
    });
  });
}
