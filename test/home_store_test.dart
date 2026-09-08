import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/pairing/home_store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HomeStore> _store() async {
  final dir = await Directory.systemTemp.createTemp('home_store_test');
  addTearDown(() => dir.delete(recursive: true));
  return HomeStore.load(dir: dir);
}

void main() {
  test('começa no padrão', () async {
    final store = await _store();
    expect(store.config.titulo, 'Celita');
    expect(store.config.busca, isTrue);
    expect(store.config.buscador, kBuscadorGoogle);
    expect(store.config.atalhos, isEmpty);
  });

  test('recusa endereço que não é http nem https', () async {
    final store = await _store();
    for (final url in ['javascript:alert(1)', 'data:text/html,x', 'ftp://a/b', 'sem-esquema']) {
      expect(await store.adicionar('x', url), isFalse, reason: url);
    }
    expect(store.config.atalhos, isEmpty);
  });

  test('aceita http e https', () async {
    final store = await _store();
    expect(await store.adicionar('Drive', 'https://drive.google.com/'), isTrue);
    expect(await store.adicionar('Interno', 'http://10.0.0.5/'), isTrue);
    expect(store.config.atalhos.map((a) => a.label), ['Drive', 'Interno']);
  });

  test('sem nome usa o domínio', () async {
    final store = await _store();
    await store.adicionar('   ', 'https://poki.com/jogos');
    expect(store.config.atalhos.single.label, 'poki.com');
  });

  test('corta nome e título compridos', () async {
    final store = await _store();
    await store.adicionar('a' * 100, 'https://exemplo.com/');
    expect(store.config.atalhos.single.label.length, kMaxLabelHome);
    await store.definirTitulo('t' * 100);
    expect(store.config.titulo.length, kMaxTituloHome);
  });

  test('título vazio volta ao padrão', () async {
    final store = await _store();
    await store.definirTitulo('Escola');
    await store.definirTitulo('   ');
    expect(store.config.titulo, 'Celita');
  });

  test('não passa do limite de atalhos', () async {
    final store = await _store();
    for (var i = 0; i < kMaxAtalhosHome; i++) {
      expect(await store.adicionar('a$i', 'https://e$i.com/'), isTrue);
    }
    expect(await store.adicionar('sobra', 'https://sobra.com/'), isFalse);
    expect(store.config.atalhos.length, kMaxAtalhosHome);
  });

  test('editar recusa endereço inválido e mantém o antigo', () async {
    final store = await _store();
    await store.adicionar('Drive', 'https://drive.google.com/');
    expect(await store.editarEm(0, 'Mau', 'javascript:alert(1)'), isFalse);
    expect(store.config.atalhos.single.url, 'https://drive.google.com/');
  });

  test('remover e reordenar', () async {
    final store = await _store();
    await store.adicionar('um', 'https://um.com/');
    await store.adicionar('dois', 'https://dois.com/');
    await store.adicionar('tres', 'https://tres.com/');
    await store.mover(2, 0);
    expect(store.config.atalhos.map((a) => a.label), ['tres', 'um', 'dois']);
    await store.removerEm(1);
    expect(store.config.atalhos.map((a) => a.label), ['tres', 'dois']);
  });

  test('buscador desconhecido vira google', () async {
    final store = await _store();
    await store.definirBuscador('bing');
    expect(store.config.buscador, kBuscadorGoogle);
    await store.definirBuscador(kBuscadorDuckDuckGo);
    expect(store.config.buscador, kBuscadorDuckDuckGo);
  });

  test('sobrevive a reabrir o app', () async {
    final dir = await Directory.systemTemp.createTemp('home_store_test');
    addTearDown(() => dir.delete(recursive: true));
    final antes = await HomeStore.load(dir: dir);
    await antes.definirTitulo('Escola');
    await antes.definirBusca(false);
    await antes.adicionar('Drive', 'https://drive.google.com/');

    final depois = await HomeStore.load(dir: dir);
    expect(depois.config.titulo, 'Escola');
    expect(depois.config.busca, isFalse);
    expect(depois.config.atalhos.single.url, 'https://drive.google.com/');
  });

  test('arquivo corrompido recomeça no padrão', () async {
    final dir = await Directory.systemTemp.createTemp('home_store_test');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/home.json').writeAsString('{lixo');
    final store = await HomeStore.load(dir: dir);
    expect(store.config.titulo, 'Celita');
  });

  test('o mapa publicado tem a forma que a página lê', () async {
    final store = await _store();
    await store.adicionar('Drive', 'https://drive.google.com/');
    final json = jsonDecode(jsonEncode(store.config.toMap())) as Map<String, dynamic>;
    expect(json.keys.toSet(), {'titulo', 'busca', 'buscador', 'atalhos'});
    expect((json['atalhos'] as List).single, {'label': 'Drive', 'url': 'https://drive.google.com/'});
  });
}
