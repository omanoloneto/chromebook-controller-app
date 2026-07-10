// Testes do histórico de aulas: derivação determinística da chave
// (mesma keypair ⇒ mesma chave; keypair diferente ⇒ indecifrável) e o
// shape de AulaMeta (encode/decode tolerante).

import 'dart:convert';

import 'package:controle_de_aula/src/cloud/history_store.dart';
import 'package:controle_de_aula/src/secure/history_crypto.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _b64url(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}

// Par fixo (mesmo do keypair_test).
const _aD = 'kLHtc7YxBsgOOgdkfgd50vy_eGvUACVycVkOsUiQX3Q';
const _aX = 'Z03jzVY4eGibMJbdDlyaM-hjbo7agkCE7LSiORqfChM';
const _bD = 'WLMjlWRflQMiHmzsgnJ1jfWuJOHhqyBy0YS4x0dnbmQ';
const _bX = 'JS-rAkqU_z8Q6eeqM32bnG47qUM0a2Iuatbgo_-24GQ';

void main() {
  group('historyCryptoFrom', () {
    test('determinística: mesma keypair abre o que selou', () async {
      final teacher = await DeviceKeyPair.fromBytes(_b64url(_aD), _b64url(_aX));
      final c1 = await historyCryptoFrom(teacher);
      final env = await c1.seal({'aluno': 'William', 'x': 1});

      final mesmoProfessor =
          await DeviceKeyPair.fromBytes(_b64url(_aD), _b64url(_aX));
      final c2 = await historyCryptoFrom(mesmoProfessor);
      final aberto = await c2.open(env);
      expect(aberto['aluno'], 'William');
    });

    test('keypair diferente (reinstalação) NÃO decifra', () async {
      final teacher = await DeviceKeyPair.fromBytes(_b64url(_aD), _b64url(_aX));
      final outra = await DeviceKeyPair.fromBytes(_b64url(_bD), _b64url(_bX));
      final env =
          await (await historyCryptoFrom(teacher)).seal({'aluno': 'W'});
      final cryptoErrado = await historyCryptoFrom(outra);
      expect(() => cryptoErrado.open(env), throwsA(anything));
    });
  });

  group('AulaMeta', () {
    test('roundtrip toMap/fromMap', () {
      final meta = AulaMeta(
        sessionId: '1767369600000',
        turma: '2º ano A',
        inicio: DateTime.fromMillisecondsSinceEpoch(1767369600000),
        fim: DateTime.fromMillisecondsSinceEpoch(1767373200000),
        alunos: {'William', 'Maria'},
      );
      final volta = AulaMeta.fromMap('1767369600000', meta.toMap())!;
      expect(volta.turma, '2º ano A');
      expect(volta.inicio, meta.inicio);
      expect(volta.fim, meta.fim);
      expect(volta.alunos, {'William', 'Maria'});
    });

    test('sem fim (aula em andamento) e malformados', () {
      final aberta = AulaMeta.fromMap('1', {
        'turma': 'A',
        'inicio': 1000,
        'alunos': ['Zé', 42, ''],
      })!;
      expect(aberta.fim, isNull);
      expect(aberta.alunos, {'Zé'}); // entradas inválidas puladas

      expect(AulaMeta.fromMap('1', {'inicio': 1}), isNull); // sem turma
      expect(AulaMeta.fromMap('1', 'não é mapa'), isNull);
    });
  });
}
