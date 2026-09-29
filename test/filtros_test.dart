import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/commands/domain_rules.dart';
import 'package:controle_de_aula/src/commands/filtros.dart';
import 'package:controle_de_aula/src/pairing/rules_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizarCanal segue o vetor compartilhado com a extensão', () {
    final casos = (jsonDecode(File('test/fixtures/filtros-canais.json')
        .readAsStringSync(),)['casos'] as List);
    for (final c in casos) {
      expect(normalizarCanal(c['entrada'] as String), c['saida'],
          reason: c['entrada'] as String,);
    }
  });

  test(
      'Filtros.fromMap: ausente = tudo ligado; canais normalizados sem repetição',
      () {
    final padrao = Filtros.fromMap(null);
    expect([padrao.shorts, padrao.reels, padrao.tiktok, padrao.ias],
        [true, true, true, true],);
    final f = Filtros.fromMap({
      'ias': false,
      'canais': ['@A.b1', 'a.b1', 'lixo com espaço', 3],
    });
    expect(f.ias, false);
    expect(f.shorts, true);
    expect(f.canais, ['@a.b1']);
    expect(Filtros.fromMap(f.toMap()).toMap(), f.toMap());
  });

  test('set_rules leva os filtros; telão vai sem nenhum', () {
    final regras = [DomainRule(pattern: 'a.com', action: RuleAction.block)];
    final cmd = buildSetRules(regras,
        rev: 1, filtros: const Filtros(shorts: false, canais: ['@x.canal']),);
    expect(cmd['payload']['filtros'], {
      'shorts': false,
      'reels': true,
      'tiktok': true,
      'ias': true,
      'canais': ['@x.canal'],
    });
    expect(
        buildSetRules(const [], rev: 2, filtros: Filtros.nenhum)['payload']
            ['filtros'],
        {
          'shorts': false,
          'reels': false,
          'tiktok': false,
          'ias': false,
          'canais': [],
        });
    expect(buildLiberarIas(liberar: true)['payload'], {'liberar': true});
  });

  test('relatório: motivo do bloqueio e IAs liberadas', () {
    final r = TabReport.fromMap({
      'type': 'tab_report',
      'tabs': [],
      'events': [
        {
          'url': 'https://youtube.com/shorts/a',
          'title': '',
          'ts': 1,
          'bloqueio': 'shorts',
        },
        {'url': 'https://a.com/', 'title': '', 'ts': 2},
      ],
      'iasLiberadas': true,
    })!;
    expect(r.events.map((e) => e.bloqueio), ['shorts', null]);
    expect(r.iasLiberadas, true);
    expect(TabReport.fromMap({'type': 'tab_report'})!.iasLiberadas, false);
    expect(descricaoBloqueio('ia'), 'uma IA');
    expect(descricaoBloqueio('regra'), isNull);
  });

  test('RulesStore guarda os filtros no mesmo arquivo das regras', () async {
    final dir = await Directory.systemTemp.createTemp('filtros');
    addTearDown(() => dir.delete(recursive: true));
    final store = await RulesStore.load(dir: dir);
    expect(store.filtros.ias, true);
    await store.adicionar('a.com', RuleAction.block);
    await store.definirFiltros(
        store.filtros.copyWith(ias: false, canais: ['@x.canal']),);
    final relido = await RulesStore.load(dir: dir);
    expect(relido.filtros.ias, false);
    expect(relido.filtros.canais, ['@x.canal']);
    expect(relido.regras.single.pattern, 'a.com');
  });
}
