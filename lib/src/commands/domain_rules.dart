// Regras de domínio (bloqueio/alerta) — spec normativa em docs/protocolo.md §3.2.
// O matching precisa casar EXATAMENTE com a extensão (src/lib/rules.js);
// vetores compartilhados em test/rules_test.dart e tests/rules.test.mjs.

const int kMaxRules = 1000;
const int kMaxRulePattern = 200;

class RuleAction {
  static const String block = 'block';
  static const String alert = 'alert';
}

class DomainRule {
  DomainRule({required this.pattern, required this.action});

  final String pattern; // já normalizado (ver normalizarPadrao)
  final String action; // RuleAction.block | RuleAction.alert

  Map<String, dynamic> toMap() => {'pattern': pattern, 'action': action};

  static DomainRule? fromMap(dynamic m) {
    if (m is! Map) return null;
    final pattern = m['pattern'];
    if (pattern is! String || pattern.isEmpty) return null;
    final action = m['action'] == RuleAction.alert ? RuleAction.alert : RuleAction.block;
    return DomainRule(pattern: pattern, action: action);
  }
}

/// Normaliza um padrão digitado: trim, minúsculas, sem esquema, sem porta,
/// sem `/` final. `www.` NÃO é removido (subdomínio já casa via hostCasa).
String normalizarPadrao(String p) {
  var s = p.trim().toLowerCase();
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  final barra = s.indexOf('/');
  var host = barra == -1 ? s : s.substring(0, barra);
  final resto = barra == -1 ? '' : s.substring(barra);
  final doisPontos = host.indexOf(':');
  if (doisPontos != -1) host = host.substring(0, doisPontos);
  s = (host + resto).replaceFirst(RegExp(r'/+$'), '');
  return s.length > kMaxRulePattern ? s.substring(0, kMaxRulePattern) : s;
}

/// Host casa com padrão de domínio: igual ou subdomínio.
bool hostCasa(String host, String pattern) {
  return host == pattern || host.endsWith('.$pattern');
}

/// Uma regra (já normalizada) casa com a URL?
bool regraCasa(String pattern, String url) {
  if (pattern.isEmpty) return false;
  Uri u;
  try {
    u = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  final host = u.host.toLowerCase();
  if (host.isEmpty) return false;
  final barra = pattern.indexOf('/');
  if (barra == -1) return hostCasa(host, pattern);
  final pHost = pattern.substring(0, barra);
  final pPath = pattern.substring(barra); // inclui o '/'
  return hostCasa(host, pHost) && u.path.toLowerCase().startsWith(pPath);
}

/// Primeira regra que casa com a URL (opcionalmente filtrando por ações), ou null.
DomainRule? acharRegra(List<DomainRule> rules, String url, {Set<String>? acoes}) {
  for (final r in rules) {
    if (acoes != null && !acoes.contains(r.action)) continue;
    if (regraCasa(r.pattern, url)) return r;
  }
  return null;
}
