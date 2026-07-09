// Regras de domínio: matcher (vetores do protocolo, espelho do rules.js),
// RulesStore, builders, alerta no registry, fila com substituição e paridade
// JS<->Dart do comando set_rules.

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/commands/domain_rules.dart';
import 'package:controle_de_aula/src/pairing/rules_store.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matcher (vetores do protocolo — iguais ao tests/rules.test.mjs)', () {
    const vetores = [
      ('youtube.com', 'https://www.youtube.com/watch?v=1', true),
      ('youtube.com', 'https://m.youtube.com/', true),
      ('youtube.com', 'http://youtube.com', true),
      ('youtube.com', 'https://notyoutube.com/', false),
      ('youtube.com', 'chrome://extensions', false),
      ('youtube.com', 'não é url', false),
      ('reddit.com/r/games', 'https://www.reddit.com/r/games/top', true),
      ('reddit.com/r/games', 'https://reddit.com/r/games', true),
      ('reddit.com/r/games', 'https://reddit.com/r/other', false),
      ('reddit.com/r/games', 'https://reddit.com/R/GAMES', true),
      ('', 'https://youtube.com/', false),
    ];

    test('regraCasa segue a tabela', () {
      for (final (pattern, url, esperado) in vetores) {
        expect(regraCasa(pattern, url), esperado, reason: '$pattern × $url');
      }
    });

    test('normalizarPadrao limpa esquema, porta, barra final e maiúsculas', () {
      expect(normalizarPadrao('  HTTPS://WWW.YouTube.com:443/  '), 'www.youtube.com');
      expect(normalizarPadrao('Reddit.com/r/Games/'), 'reddit.com/r/games');
      expect(normalizarPadrao('youtube.com'), 'youtube.com');
      expect(normalizarPadrao('http://a.com:8080/x'), 'a.com/x');
    });

    test('acharRegra respeita filtro de ações', () {
      final regras = [
        DomainRule(pattern: 'a.com', action: RuleAction.alert),
        DomainRule(pattern: 'b.com', action: RuleAction.block),
      ];
      expect(acharRegra(regras, 'https://a.com/')!.action, RuleAction.alert);
      expect(
        acharRegra(regras, 'https://a.com/', acoes: {RuleAction.block}),
        isNull,
      );
      expect(acharRegra(regras, 'https://c.com/'), isNull);
    });
  });

  group('RulesStore', () {
    test('round-trip com normalização e sem duplicatas', () async {
      final dir = await Directory.systemTemp.createTemp('rules_test');
      try {
        final store = await RulesStore.load(dir: dir);
        await store.adicionar('HTTPS://YouTube.com/', RuleAction.block);
        await store.adicionar('youtube.com', RuleAction.alert); // substitui
        await store.adicionar('reddit.com/r/games', RuleAction.block);
        expect(store.regras, hasLength(2));
        expect(store.rev, greaterThan(0));

        final relido = await RulesStore.load(dir: dir);
        expect(relido.regras, hasLength(2));
        expect(relido.regras[0].pattern, 'youtube.com');
        expect(relido.regras[0].action, RuleAction.alert);

        await relido.removerEm(0);
        expect((await RulesStore.load(dir: dir)).regras, hasLength(1));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('builders', () {
    test('buildCloseTabs exige exatamente um alvo', () {
      final porDominio = buildCloseTabs(domain: 'youtube.com');
      expect(porDominio['type'], MessageType.closeTabs);
      expect(porDominio['payload'], {'domain': 'youtube.com'});
      final porUrl = buildCloseTabs(url: 'https://x.com/a');
      expect(porUrl['payload'], {'url': 'https://x.com/a'});
    });

    test('buildSetRules só envia regras block', () {
      final cmd = buildSetRules(
        [
          DomainRule(pattern: 'youtube.com', action: RuleAction.block),
          DomainRule(pattern: 'espiar.com', action: RuleAction.alert),
        ],
        rev: 42,
      );
      final payload = cmd['payload'] as Map<String, dynamic>;
      expect(payload['rev'], 42);
      expect(payload['rules'], [
        {'pattern': 'youtube.com'},
      ]);
    });

    test('buildSetWallpaper carrega o hash', () {
      expect(buildSetWallpaper('9f2ab41c')['payload'], {'hash': '9f2ab41c'});
    });
  });

  group('SessionRegistry: alertas', () {
    final chave = List<int>.generate(32, (i) => i);

    test('applyReport seta e limpa o alerta via avaliarAlerta', () {
      final reg = SessionRegistry();
      reg.avaliarAlerta = (deviceId, tabs) {
        for (final t in tabs) {
          if (regraCasa('youtube.com', t.url)) return Uri.parse(t.url).host;
        }
        return null;
      };
      reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave);
      reg.applyReport(
        'pc1',
        TabReport(
          tabs: [
            TabInfo(url: 'https://m.youtube.com/w', title: 'y', active: true),
          ],
          events: const [],
        ),
      );
      expect(reg.byId('pc1')!.alerta, 'm.youtube.com');
      reg.applyReport('pc1', TabReport(tabs: const [], events: const []));
      expect(reg.byId('pc1')!.alerta, isNull);
    });

    // (A fila por sessão morreu no v4: comandos vão direto ao RTDB — comandos
    // de estado viram snapshot em state/*, ver firebase_transport.dart.)
  });

  group('paridade JS <-> Dart (set_rules)', () {
    // Envelope selado pelo crypto.js real (key 0..31, nonce 0..11).
    const envelopeDoJs =
        'AAECAwQFBgcICQoLPCCgOf/U7jn5OOfuk9NaHuai2EaFFzoPGkvH7HlLOpBgJJveg+Ni'
        '+Q3IEIzspRJDzCsF+3jsku0JoBkvIdXF3sAM9lbxo1MNeSeIVLT0LJhZ/r0HBA1xUt+E'
        '8bkMhdvo5Zs2i4Y85GG8bF/GPBBTEZhdQNmGoUHzOdE0ou/JHCHcM22jx/W2DnXNatJY'
        'q274BdjBQUYzqXu7ad9EzOvf3qOnriWURiJmNptYwR1i8RNn2ZQEpg==';

    test('comando montado no Dart tem os mesmos campos que o JS decifra', () async {
      final c = SessionCrypto(List<int>.generate(32, (i) => i));
      final msg = await c.open(envelopeDoJs);
      expect(msg['type'], 'set_rules');

      // Compara com o buildSetRules (mesmos nomes de campos no fio).
      final construido = buildSetRules(
        [
          DomainRule(pattern: 'youtube.com', action: RuleAction.block),
          DomainRule(pattern: 'reddit.com/r/games', action: RuleAction.block),
        ],
        rev: 1767369600000,
      );
      final payloadFio = jsonEncode(msg['payload']);
      final payloadDart = jsonEncode(construido['payload']);
      expect(payloadDart, payloadFio);
    });
  });
}
