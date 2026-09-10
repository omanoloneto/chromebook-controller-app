// Página inicial que os alunos veem ao abrir o navegador (escolacelita.com/home).
// Diferente do resto do app, isto não é comando de PC: é uma configuração só da
// escola, publicada em claro, que a própria página lê. Por isso mora num store
// simples, sem envelope e sem device.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'favorites_store.dart';

/// Limites repetidos nas regras do banco e na página. Aqui eles servem para o
/// professor nunca conseguir publicar algo que a página vai descartar calada.
const int kMaxAtalhosHome = 12;
const int kMaxLabelHome = 24;
const int kMaxTituloHome = 20;
const int kMaxUrlHome = 2048;

const String kBuscadorGoogle = 'google';
const String kBuscadorDuckDuckGo = 'duckduckgo';

class PaginaInicial {
  const PaginaInicial({
    required this.titulo,
    required this.busca,
    required this.buscador,
    required this.atalhos,
    this.url = '',
  });

  final String titulo;
  final bool busca;
  final String buscador;
  final List<Favorito> atalhos;

  /// Site aberto no lugar da página do Celita; vazio = a página.
  final String url;

  static const PaginaInicial padrao = PaginaInicial(
    titulo: 'Celita',
    busca: true,
    buscador: kBuscadorGoogle,
    atalhos: [],
  );

  PaginaInicial copyWith({
    String? titulo,
    bool? busca,
    String? buscador,
    List<Favorito>? atalhos,
    String? url,
  }) => PaginaInicial(
    titulo: titulo ?? this.titulo,
    busca: busca ?? this.busca,
    buscador: buscador ?? this.buscador,
    atalhos: atalhos ?? this.atalhos,
    url: url ?? this.url,
  );

  Map<String, dynamic> toMap() => {
    'titulo': titulo,
    'busca': busca,
    'buscador': buscador,
    'atalhos': atalhos.map((a) => a.toMap()).toList(),
    'url': url,
  };

  static PaginaInicial fromMap(dynamic m) {
    if (m is! Map) return padrao;
    final lista = m['atalhos'];
    final atalhos = lista is List
        ? lista.map(Favorito.fromMap).whereType<Favorito>().take(kMaxAtalhosHome).toList()
        : <Favorito>[];
    final titulo = m['titulo'];
    final buscador = m['buscador'];
    final url = m['url'];
    return PaginaInicial(
      titulo: titulo is String && titulo.trim().isNotEmpty
          ? _cortar(titulo.trim(), kMaxTituloHome)
          : padrao.titulo,
      busca: m['busca'] != false,
      buscador: buscador == kBuscadorDuckDuckGo ? kBuscadorDuckDuckGo : kBuscadorGoogle,
      atalhos: atalhos,
      url: url is String && url.trim().length <= kMaxUrlHome && urlDeAtalhoValida(url)
          ? url.trim()
          : '',
    );
  }
}

String _cortar(String valor, int limite) =>
    valor.length <= limite ? valor : valor.substring(0, limite);

/// Só http e https viram atalho: a página recusaria o resto de qualquer forma,
/// e recusar aqui deixa o erro visível para quem está digitando.
bool urlDeAtalhoValida(String url) {
  final destino = Uri.tryParse(url.trim());
  if (destino == null || !destino.hasAuthority) return false;
  return destino.scheme == 'http' || destino.scheme == 'https';
}

class HomeStore {
  HomeStore._(this._file, this._config);

  static const _fileName = 'home.json';

  final File _file;
  PaginaInicial _config;

  /// `dir` é injetável para testes; por padrão usa o diretório do app.
  static Future<HomeStore> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$_fileName');
    var config = PaginaInicial.padrao;
    if (await file.exists()) {
      try {
        config = PaginaInicial.fromMap(jsonDecode(await file.readAsString()));
      } catch (_) {
        // arquivo corrompido -> recomeça no padrão
      }
    }
    return HomeStore._(file, config);
  }

  PaginaInicial get config => _config;

  Future<void> definirTitulo(String titulo) async {
    final novo = titulo.trim();
    _config = _config.copyWith(
      titulo: novo.isEmpty ? PaginaInicial.padrao.titulo : _cortar(novo, kMaxTituloHome),
    );
    await _save();
  }

  /// Site no lugar da página do Celita. Vazio volta para a página; false =
  /// endereço recusado (só http e https).
  Future<bool> definirUrl(String url) async {
    final novo = url.trim();
    if (novo.isNotEmpty && (novo.length > kMaxUrlHome || !urlDeAtalhoValida(novo))) {
      return false;
    }
    _config = _config.copyWith(url: novo);
    await _save();
    return true;
  }

  Future<void> definirBusca(bool ligada) async {
    _config = _config.copyWith(busca: ligada);
    await _save();
  }

  Future<void> definirBuscador(String buscador) async {
    _config = _config.copyWith(
      buscador: buscador == kBuscadorDuckDuckGo ? kBuscadorDuckDuckGo : kBuscadorGoogle,
    );
    await _save();
  }

  /// Retorna false quando o endereço não serve ou a lista já está cheia.
  Future<bool> adicionar(String label, String url) async {
    final endereco = url.trim();
    if (!urlDeAtalhoValida(endereco)) return false;
    if (_config.atalhos.length >= kMaxAtalhosHome) return false;
    final nome = label.trim();
    final atalhos = [
      ..._config.atalhos,
      Favorito(
        label: _cortar(nome.isEmpty ? Uri.parse(endereco).host : nome, kMaxLabelHome),
        url: endereco,
      ),
    ];
    _config = _config.copyWith(atalhos: atalhos);
    await _save();
    return true;
  }

  Future<bool> editarEm(int indice, String label, String url) async {
    if (indice < 0 || indice >= _config.atalhos.length) return false;
    final endereco = url.trim();
    if (!urlDeAtalhoValida(endereco)) return false;
    final nome = label.trim();
    final atalhos = [..._config.atalhos];
    atalhos[indice] = Favorito(
      label: _cortar(nome.isEmpty ? Uri.parse(endereco).host : nome, kMaxLabelHome),
      url: endereco,
    );
    _config = _config.copyWith(atalhos: atalhos);
    await _save();
    return true;
  }

  Future<void> removerEm(int indice) async {
    if (indice < 0 || indice >= _config.atalhos.length) return;
    final atalhos = [..._config.atalhos]..removeAt(indice);
    _config = _config.copyWith(atalhos: atalhos);
    await _save();
  }

  /// Reordena (semântica do ReorderableListView).
  Future<void> mover(int de, int para) async {
    if (de < 0 || de >= _config.atalhos.length) return;
    var destino = para;
    if (destino > de) destino -= 1;
    final atalhos = [..._config.atalhos];
    final item = atalhos.removeAt(de);
    atalhos.insert(destino.clamp(0, atalhos.length), item);
    _config = _config.copyWith(atalhos: atalhos);
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(jsonEncode(_config.toMap()));
  }
}
