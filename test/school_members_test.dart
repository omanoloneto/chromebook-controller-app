// Escola fechada: chave de e-mail igual à das rules e do agente do Celita.

import 'dart:async';

import 'package:controle_de_aula/src/cloud/school_members.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emailKey: minúsculas e todo "." vira ","', () {
    expect(emailKey('ana.silva@escola.com.br'), 'ana,silva@escola,com,br');
    expect(emailKey('Ana.Silva@Escola.COM.br'), 'ana,silva@escola,com,br');
    expect(emailKey('prof@gmail.com'), 'prof@gmail,com');
  });

  test('emailDaChave desfaz a troca para exibir', () {
    expect(emailDaChave('ana,silva@escola,com,br'), 'ana.silva@escola.com.br');
    expect(emailDaChave(emailKey('a.b.c@d.e')), 'a.b.c@d.e');
  });

  test('normalizarEmail aceita e-mails comuns e normaliza', () {
    expect(normalizarEmail('  Ana.Silva@Escola.com.br '), 'ana.silva@escola.com.br');
    expect(normalizarEmail("o'neil+aula_1@x-y.com"), "o'neil+aula_1@x-y.com");
  });

  test(r'normalizarEmail recusa $ # [ ] / espaço e formatos quebrados', () {
    for (final ruim in [
      r'a$b@x.com',
      'a#b@x.com',
      'a[b@x.com',
      'a]b@x.com',
      'a/b@x.com',
      'a b@x.com',
      'sem-arroba.com',
      'a@b@c.com',
      '@x.com',
      'a@',
      '',
      'á@x.com',
    ]) {
      expect(normalizarEmail(ruim), isNull, reason: ruim);
    }
  });

  test('texto único de não liberado leva o e-mail', () {
    expect(
      textoNaoLiberado('ana@x.com'),
      'Seu e-mail (ana@x.com) ainda não foi liberado. Peça ao professor que '
      'criou a escola para liberar em Ajustes → Professores da escola.',
    );
  });

  group('liberadoAoAbrir', () {
    test('permission-denied ou ausente (false) barra', () async {
      expect(await liberadoAoAbrir(() async => false), isFalse);
      expect(await liberadoAoAbrir(() async => true), isTrue);
    });

    test('sem rede (erro que não é permission-denied) deixa seguir', () async {
      expect(
        await liberadoAoAbrir(
          () async => throw FirebaseException(
            plugin: 'firebase_database',
            code: 'unavailable',
            message: 'Client is offline',
          ),
        ),
        isTrue,
      );
    });

    test('consulta que não responde deixa seguir depois do limite', () async {
      expect(
        await liberadoAoAbrir(
          () => Completer<bool>().future,
          limite: const Duration(milliseconds: 10),
        ),
        isTrue,
      );
    });
  });
}
