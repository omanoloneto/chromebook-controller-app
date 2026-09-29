// Filtros prontos de vídeos curtos, canais e IAs — espelho de
// src/lib/filtros.js da extensão (paridade: test/fixtures/filtros-canais.json).
// A extensão aplica; aqui só se configura e se valida o que o professor digita.

const int kMaxCanais = 200;

class Filtros {
  const Filtros({
    this.shorts = true,
    this.reels = true,
    this.tiktok = true,
    this.ias = true,
    this.canais = const [],
  });

  /// Pedido do usuário: tudo chega ligado; o professor desliga no app.
  static const padrao = Filtros();

  /// Computador do Professor: o telão precisa abrir qualquer coisa.
  static const nenhum = Filtros(shorts: false, reels: false, tiktok: false, ias: false);

  final bool shorts;
  final bool reels;
  final bool tiktok;
  final bool ias;
  final List<String> canais;

  Filtros copyWith({bool? shorts, bool? reels, bool? tiktok, bool? ias, List<String>? canais}) => Filtros(
        shorts: shorts ?? this.shorts,
        reels: reels ?? this.reels,
        tiktok: tiktok ?? this.tiktok,
        ias: ias ?? this.ias,
        canais: canais ?? this.canais,
      );

  Map<String, dynamic> toMap() => {
        'shorts': shorts,
        'reels': reels,
        'tiktok': tiktok,
        'ias': ias,
        'canais': canais,
      };

  /// Chave ausente = padrão (tudo ligado); canais inválidos são descartados.
  static Filtros fromMap(dynamic m) {
    if (m is! Map) return padrao;
    bool b(String k) => m[k] is bool ? m[k] as bool : true;
    final canais = <String>[];
    final raw = m['canais'];
    if (raw is List) {
      for (final c in raw) {
        final n = c is String ? normalizarCanal(c) : null;
        if (n != null && !canais.contains(n)) canais.add(n);
        if (canais.length >= kMaxCanais) break;
      }
    }
    return Filtros(shorts: b('shorts'), reels: b('reels'), tiktok: b('tiktok'), ias: b('ias'), canais: canais);
  }
}

final _urlYoutube = RegExp(r'^(?:https?://)?(?:[a-z0-9-]+\.)*youtube\.com(/[^?#]*)?', caseSensitive: false);
final _canalId = RegExp(r'^UC[A-Za-z0-9_-]{22}$');
final _canalHandle = RegExp(r'^@[A-Za-z0-9._-]{3,30}$');

/// '@Canal', 'canal', link do canal (youtube.com/@canal ou /channel/UC…) ou o
/// id 'UC…' → '@canal' (minúsculo) ou o id. Inválido → null.
String? normalizarCanal(String texto) {
  var s = texto.trim();
  if (s.isEmpty) return null;
  final url = _urlYoutube.firstMatch(s);
  if (url != null) {
    final partes = (url.group(1) ?? '').split('/').where((p) => p.isNotEmpty).toList();
    if (partes.isNotEmpty && partes[0].startsWith('@')) {
      s = partes[0];
    } else if (partes.length > 1 && partes[0] == 'channel') {
      s = partes[1];
    } else {
      return null;
    }
  }
  try {
    s = Uri.decodeComponent(s);
  } catch (_) {
    return null;
  }
  if (_canalId.hasMatch(s)) return s;
  if (!s.startsWith('@')) s = '@$s';
  return _canalHandle.hasMatch(s) ? s.toLowerCase() : null;
}

/// Texto leigo do motivo que a extensão marcou numa tentativa bloqueada.
String? descricaoBloqueio(String? motivo) => switch (motivo) {
      'shorts' => 'Shorts do YouTube',
      'reels' => 'Reels do Instagram',
      'tiktok' => 'TikTok',
      'ia' => 'uma IA',
      'canal' => 'um canal bloqueado do YouTube',
      _ => null,
    };
