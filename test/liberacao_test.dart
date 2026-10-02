// Pedido de liberação: quais regras "Liberar" tira daquele PC e a validação
// do site pedido (SPEC-turma §2.2 e §4.4).

import 'package:controle_de_aula/src/commands/domain_rules.dart';
import 'package:controle_de_aula/src/commands/liberacao.dart';
import 'package:flutter_test/flutter_test.dart';

DomainRule _b(String p) => DomainRule(pattern: p, action: RuleAction.block);
DomainRule _a(String p) => DomainRule(pattern: p, action: RuleAction.alert);

void main() {
  group('padroesQueCasam', () {
    test('youtube.com e youtube.com/shorts casam m.youtube.com/shorts/x', () {
      final regras = [_b('youtube.com'), _b('youtube.com/shorts'), _b('tiktok.com')];
      expect(
        padroesQueCasam(regras, 'https://m.youtube.com/shorts/x'),
        ['youtube.com', 'youtube.com/shorts'],
      );
    });

    test('só regras de bloqueio; alerta não entra', () {
      final regras = [_a('youtube.com'), _b('youtube.com/shorts')];
      expect(padroesQueCasam(regras, 'https://www.youtube.com/shorts/x'), ['youtube.com/shorts']);
      expect(padroesQueCasam(regras, 'https://www.youtube.com/watch?v=1'), isEmpty);
    });

    test('nenhuma regra casando (as regras mudaram) = lista vazia', () {
      expect(padroesQueCasam([_b('tiktok.com')], 'https://youtube.com/'), isEmpty);
      expect(padroesQueCasam(const [], 'https://youtube.com/'), isEmpty);
    });

    test('sem URL no pedido, casa pela raiz do site', () {
      expect(urlParaCasar('', 'youtube.com'), 'https://youtube.com/');
      expect(urlParaCasar('https://a.youtube.com/x', 'youtube.com'), 'https://a.youtube.com/x');
      expect(padroesQueCasam([_b('youtube.com')], urlParaCasar('', 'youtube.com')), ['youtube.com']);
    });
  });

  group('siteValido', () {
    test('aceita host com 2+ rótulos', () {
      expect(siteValido('pt.khanacademy.org'), isTrue);
      expect(siteValido('youtube.com'), isTrue);
      expect(siteValido('escola.edu.br'), isTrue);
      expect(siteValido('a-b.c0.net'), isTrue);
    });

    test('recusa sufixo público da lista curta', () {
      for (final s in ['com', 'com.br', 'gov.br', 'edu.br', 'net.br', 'org.br', 'io', 'dev', 'app']) {
        expect(siteValido(s), isFalse, reason: s);
      }
    });

    test('recusa formato errado', () {
      expect(siteValido(null), isFalse);
      expect(siteValido(''), isFalse);
      expect(siteValido('YouTube.com'), isFalse, reason: 'só minúsculas');
      expect(siteValido('youtube'), isFalse, reason: '1 rótulo');
      expect(siteValido('youtube..com'), isFalse, reason: 'rótulo vazio');
      expect(siteValido('.youtube.com'), isFalse);
      expect(siteValido('youtube.com/'), isFalse);
      expect(siteValido('you tube.com'), isFalse);
      expect(siteValido('${'a' * 98}.com'), isFalse, reason: '> 100');
    });
  });

  group('urlDoSite', () {
    test('URL tem de ser do site (igual ou subdomínio), http(s)', () {
      expect(urlDoSite('https://www.youtube.com/watch', 'youtube.com'), isTrue);
      expect(urlDoSite('https://youtube.com/', 'youtube.com'), isTrue);
      expect(urlDoSite('', 'youtube.com'), isTrue);
      expect(urlDoSite('https://evilyoutube.com/', 'youtube.com'), isFalse);
      expect(urlDoSite('https://khanacademy.org/', 'youtube.com'), isFalse);
      expect(urlDoSite('javascript:alert(1)', 'youtube.com'), isFalse);
    });
  });
}
