// Os dois arquivos compartilhados com a extensão (rules e protocolo) têm de
// ser idênticos byte a byte nos dois repositórios. A extensão é a autora; o
// app copia com `cp` e confere o hash gravado em
// test/fixtures/compartilhados.sha256 (a extensão grava o mesmo arquivo em
// tests/fixtures/compartilhados.sha256).

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final linhas = File('test/fixtures/compartilhados.sha256')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  test('o arquivo de hash lista os dois arquivos compartilhados', () {
    final caminhos = [for (final l in linhas) l.split(RegExp(r'\s+')).last];
    expect(caminhos, ['firebase/database.rules.json', 'docs/protocolo.md']);
  });

  for (final linha in linhas) {
    final partes = linha.split(RegExp(r'\s+'));
    final esperado = partes.first;
    final caminho = partes.last;
    test('$caminho tem o hash combinado com a extensão', () {
      final atual = sha256.convert(File(caminho).readAsBytesSync()).toString();
      expect(
        atual,
        esperado,
        reason: '$caminho mudou: copie de novo da extensão (cp) e atualize '
            'test/fixtures/compartilhados.sha256 nos dois repositórios.',
      );
    });
  }
}
