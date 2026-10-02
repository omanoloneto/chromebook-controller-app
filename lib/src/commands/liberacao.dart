// Pedido de liberação (item 27): validação do `site` que o aluno pediu e quais
// regras de bloqueio o "Liberar" precisa tirar daquele PC. Puro — testável
// (test/liberacao_test.dart). Ver SPEC-turma §2.2 e §4.4.

import 'domain_rules.dart';

/// Sufixos públicos da lista curta do protocolo: um pedido para um deles
/// liberaria meia internet, então é recusado.
const Set<String> kSufixosPublicos = {
  'com',
  'br',
  'net',
  'org',
  'edu',
  'gov',
  'com.br',
  'net.br',
  'org.br',
  'edu.br',
  'gov.br',
  'app',
  'dev',
  'io',
};

final RegExp _siteChars = RegExp(r'^[a-z0-9.-]{1,100}$');

/// `site` de um `unblock_request`: host minúsculo `^[a-z0-9.-]{1,100}$`, com
/// pelo menos 2 rótulos não vazios e que não seja sufixo público. Quem envia
/// valida antes; o professor valida de novo e descarta calado o que falhar.
bool siteValido(String? site) {
  if (site == null || !_siteChars.hasMatch(site)) return false;
  final rotulos = site.split('.');
  if (rotulos.length < 2 || rotulos.any((r) => r.isEmpty)) return false;
  return !kSufixosPublicos.contains(site);
}

/// Padrão largo demais para LIBERAR na prova: o host (antes da `/`) não tem
/// ponto (casaria um domínio de topo inteiro, ex.: `co`) ou é sufixo público
/// (`com.br` liberaria todo site .com.br). Um erro de digitação desses abriria
/// meia internet durante a prova, então a lista da prova o recusa.
bool padraoAmploDemais(String pattern) {
  final barra = pattern.indexOf('/');
  final host = barra == -1 ? pattern : pattern.substring(0, barra);
  return host.isEmpty || !host.contains('.') || kSufixosPublicos.contains(host);
}

/// O `url` do pedido é mesmo do `site` (igual ou subdomínio)? Sem isto um PC
/// adulterado poderia mostrar um site ao professor e liberar outro.
bool urlDoSite(String url, String site) {
  if (url.isEmpty) return true; // sem URL: só o site conta
  Uri u;
  try {
    u = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  final host = u.host.toLowerCase();
  return host == site || host.endsWith('.$site');
}

/// URL usada para casar regras: a do pedido ou, sem ela, a raiz do site.
String urlParaCasar(String url, String site) =>
    url.isNotEmpty ? url : 'https://$site/';

/// Padrões de BLOQUEIO que casam a URL pedida (normalizados, sem repetição,
/// na ordem das regras). "Liberar" fora da prova tira todos eles daquele PC;
/// lista vazia = as regras mudaram e o site já abre (aprova sem mexer).
List<String> padroesQueCasam(List<DomainRule> regras, String url) {
  final saida = <String>[];
  for (final r in regras) {
    if (r.action != RuleAction.block) continue;
    if (regraCasa(r.pattern, url) && !saida.contains(r.pattern)) {
      saida.add(r.pattern);
    }
  }
  return saida;
}
