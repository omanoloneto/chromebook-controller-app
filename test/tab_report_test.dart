// Testes do relatório de abas (tab_report) — parse, merge no registry,
// preservação no re-bind, NameStore e paridade JS<->Dart do corpo do poll.

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/pairing/name_store.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:flutter_test/flutter_test.dart';

// Exemplo do docs/protocolo.md (mesmos nomes de campos do lado JS).
const _exemploReport = '''
{
  "v": 1,
  "type": "tab_report",
  "tabs": [
    { "url": "https://pt.khanacademy.org/math", "title": "Matemática | Khan Academy", "active": true },
    { "url": "https://www.youtube.com/watch?v=abc", "title": "Vídeo qualquer", "active": false }
  ],
  "events": [
    { "url": "https://www.google.com/search?q=fotossintese", "title": "fotossintese - Pesquisa Google", "ts": 1767369540123 },
    { "url": "https://pt.khanacademy.org/math", "title": "Matemática | Khan Academy", "ts": 1767369588456 }
  ]
}
''';

TabReport _report(List<NavEvent> events, {List<TabInfo> tabs = const []}) =>
    TabReport(tabs: tabs, events: events);

NavEvent _ev(int ts, [String url = 'https://ex.com/']) =>
    NavEvent(url: url, title: 't$ts', ts: ts);

void main() {
  group('TabReport.fromMap', () {
    test('parseia o exemplo do protocolo', () {
      final m = jsonDecode(_exemploReport) as Map<String, dynamic>;
      final r = TabReport.fromMap(m)!;
      expect(r.tabs, hasLength(2));
      expect(r.tabs[0].url, 'https://pt.khanacademy.org/math');
      expect(r.tabs[0].title, 'Matemática | Khan Academy');
      expect(r.tabs[0].active, isTrue);
      expect(r.tabs[1].active, isFalse);
      expect(r.events, hasLength(2));
      expect(r.events[0].ts, 1767369540123);
      expect(r.events[1].url, 'https://pt.khanacademy.org/math');
    });

    test('retorna null para type errado', () {
      expect(TabReport.fromMap({'type': 'open_url'}), isNull);
    });

    test('pula entradas malformadas e aplica caps defensivos', () {
      final r = TabReport.fromMap({
        'type': 'tab_report',
        'tabs': [
          {'url': 'https://ok.com', 'title': 'ok'},
          {'title': 'sem url'},
          'nem é mapa',
          for (var i = 0; i < 100; i++) {'url': 'https://x$i.com'},
        ],
        'events': [
          {'url': 'https://ok.com', 'ts': 1},
          {'ts': 2},
          for (var i = 0; i < 100; i++) {'url': 'https://x$i.com', 'ts': i},
        ],
      })!;
      expect(r.tabs.length, kMaxReportTabs);
      expect(r.events.length, kMaxReportEvents);
      expect(r.tabs.first.url, 'https://ok.com');
    });
  });

  group('SessionRegistry', () {
    final chave = List<int>.generate(32, (i) => i);

    SessionRegistry novoRegistry(String deviceId) {
      final reg = SessionRegistry();
      reg.bind(deviceId: deviceId, label: 'Chromebook-a1b2', sessionKey: chave);
      return reg;
    }

    test('applyReport substitui abas e faz merge do histórico com dedup', () {
      final reg = novoRegistry('pc1');
      reg.applyReport('pc1', _report([_ev(1), _ev(2)]));
      // Log rolante reenviado inteiro + um evento novo:
      reg.applyReport('pc1', _report([_ev(1), _ev(2), _ev(3)]));
      final s = reg.byId('pc1')!;
      expect(s.history.map((e) => e.ts), [1, 2, 3]);
    });

    test('histórico é limitado a kMaxHistoryPorPc', () {
      final reg = novoRegistry('pc1');
      for (var lote = 0; lote < 30; lote++) {
        reg.applyReport(
          'pc1',
          _report([for (var i = 0; i < 10; i++) _ev(lote * 10 + i)]),
        );
      }
      final s = reg.byId('pc1')!;
      expect(s.history.length, kMaxHistoryPorPc);
      expect(s.history.last.ts, 299); // mantém os mais recentes
    });

    test('abaAtiva retorna a aba marcada como ativa', () {
      final reg = novoRegistry('pc1');
      reg.applyReport(
        'pc1',
        _report(
          const [],
          tabs: [
            TabInfo(url: 'https://a.com', title: 'A', active: false),
            TabInfo(url: 'https://b.com', title: 'B', active: true),
          ],
        ),
      );
      expect(reg.byId('pc1')!.abaAtiva!.url, 'https://b.com');
    });

    test('re-bind preserva abas e histórico (reconexão não zera)', () {
      final reg = novoRegistry('pc1');
      reg.applyReport(
        'pc1',
        _report(
          [_ev(1)],
          tabs: [TabInfo(url: 'https://a.com', title: 'A', active: true)],
        ),
      );
      // Reconexão: extensão refaz o /bind com chave de sessão nova.
      reg.bind(
        deviceId: 'pc1',
        label: 'Chromebook-a1b2',
        sessionKey: List<int>.generate(32, (i) => 255 - i),
      );
      final s = reg.byId('pc1')!;
      expect(s.history, hasLength(1));
      expect(s.tabs, hasLength(1));
      expect(s.lastReportAt, isNotNull);
    });
  });

  group('NameStore', () {
    test('round-trip: salva, recarrega, remove', () async {
      final dir = await Directory.systemTemp.createTemp('names_test');
      try {
        final store = await NameStore.load(dir: dir);
        expect(store.nameOf('pc1'), isNull);
        await store.setName('pc1', '  Maria  ');

        final relido = await NameStore.load(dir: dir);
        expect(relido.nameOf('pc1'), 'Maria');

        await relido.setName('pc1', '');
        final vazio = await NameStore.load(dir: dir);
        expect(vazio.nameOf('pc1'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('paridade JS <-> Dart', () {
    // Envelope gerado pelo lado JS (protocol.js makeTabReport + crypto.js seal)
    // com key = 0..31 e nonce = 0..11 — ver scripts em docs/protocolo.md.
    // Se quebrar, os nomes de campos ou o formato divergiram entre as linguagens.
    const envelopeDoJs =
        'AAECAwQFBgcICQoLPCCiYrWA4CGvMfjn3ctUT/Gz91uCD31GQ0WTpydYLJB1ad6Zjfsw'
        '7BXGIJ/t90dKmntMry63wakdrXFiOpaHgtIG5BKnpVYSJnuFHpuhZYBZ5KgBFwc2BYTT'
        '8b4f39Tsv5B7yoY1oW7yeRyIajhAC98KoQqXrEb7bYN3huqHAC76MWGi0bqycSTDKcJJ'
        'szqnFM6XR0B07mb3fZ0FlvDTzPvj6mWaxeNR0BSq1Kbv88/orK8M6MQekxK+tKQZ+sHO'
        'ci7p2CH/oqBDOrbEgGOPR0wanRkdcc+QHeDvojNqo9giQKDGkEUhHzQm1HvQbCF9ivbP'
        'EPNE+octMBxR/u4uoy7zmuTpqjsEWPAFcMADXWW106aorujuwl5cCDB4l9J0cD64J86q'
        'vWT7Uk4/efCC/7q+Miol8e0tuldyYvhONoCn4RpZ7kBVyfOFCFEoum4Ds1246/t44Cpl'
        'gQwVr4t5yG8Yyu+8YUb7EZ2XXrvOQF32kT1DzJl0te+WDvPzJy0czuuht+ZksrjEHYdR'
        'UTJ1qI9qGNO9DHCgVGSyI2/cmRt4DjIGAHAlG8PZ/C7fs9jEM0sFcX3nRYiem8/P8tg9'
        'QktNmOqdYYZI0yLUYsfpiCxFqBg3srgkC2/nzsMzxbeDL9gaN66l7/5hmjTwJdPOf1T/'
        '2nHm4wKTxV+JTQ==';

    test('poll+report selado no JS abre e parseia no Dart', () async {
      final c = SessionCrypto(List<int>.generate(32, (i) => i));
      final msg = await c.open(envelopeDoJs);
      expect(msg['type'], 'poll');
      expect(msg['seq'], 7);
      expect(msg['ts'], 1767369600000);

      final report = TabReport.fromMap(msg['report'] as Map<String, dynamic>)!;
      // O makeTabReport do JS filtrou a aba chrome:// — sobram 2.
      expect(report.tabs, hasLength(2));
      expect(report.tabs[0].url, 'https://pt.khanacademy.org/math');
      expect(report.tabs[0].active, isTrue);
      expect(report.events, hasLength(2));
      expect(report.events[0].title, 'fotossintese - Pesquisa Google');
      expect(report.events[1].ts, 1767369588456);
    });
  });
}
