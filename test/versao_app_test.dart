// A versão mostrada em Ajustes acompanha a do pubspec (sem o número do build).

import 'dart:io';

import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kVersaoApp é a versão do pubspec', () {
    final linha = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final versao = linha.split(':').last.trim().split('+').first;
    expect(kVersaoApp, versao);
  });
}
