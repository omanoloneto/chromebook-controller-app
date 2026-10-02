// Ids de comando e mid: 12 bytes aleatórios em base64url (16 caracteres),
// sem repetição; "pertence a mim" limitado aos últimos 500.

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/util/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('novoId: 16 caracteres base64url, sem "="', () {
    for (var i = 0; i < 100; i++) {
      final id = novoId();
      expect(id, hasLength(16));
      expect(formatoDeId.hasMatch(id), isTrue, reason: id);
      expect(id.contains('='), isFalse);
    }
  });

  test('novoId não se repete em 10⁴', () {
    final vistos = <String>{};
    for (var i = 0; i < 10000; i++) {
      expect(vistos.add(novoId()), isTrue);
    }
  });

  test('os builders usam id aleatório (não mais "a"+contador)', () {
    final a = buildOpenUrl('https://a.com')['id'] as String;
    final b = buildOpenUrl('https://a.com')['id'] as String;
    expect(formatoDeId.hasMatch(a), isTrue);
    expect(a, isNot(b));
    expect(a.startsWith('a') && int.tryParse(a.substring(1)) != null, isFalse);
  });

  test('IdsEmitidos guarda só os últimos [limite]', () {
    final ids = IdsEmitidos(limite: 3);
    for (final id in ['a', 'b', 'c', 'd']) {
      ids.registrar(id);
    }
    expect(ids.contem('a'), isFalse);
    expect(ids.contem('b'), isTrue);
    expect(ids.contem('d'), isTrue);
    expect(ids.length, 3);
    ids.registrar('b'); // reusar renova a posição
    ids.registrar('e');
    expect(ids.contem('b'), isTrue);
    expect(ids.contem('c'), isFalse);
  });
}
