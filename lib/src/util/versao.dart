// Versão do cliente de um PC (meta/ext) para exibição.

/// "celita-0.10.0" → "0.10.0"; "0.4.11" → "0.4.11"; nula/vazia → null.
String? versaoCurta(String? ext) {
  var v = ext?.trim() ?? '';
  if (v.startsWith('celita-')) v = v.substring('celita-'.length);
  return v.isEmpty ? null : v;
}

/// Nome do PC nas listas: o nome salvo + " (versão)" quando houver versão.
String nomeComVersao(String nome, String? ext) {
  final v = versaoCurta(ext);
  return v == null ? nome : '$nome ($v)';
}

/// O PC roda o Celita OS (o agente publica meta/ext = "celita-<versão>")?
bool temCelita(String? ext) => ext?.trim().startsWith('celita-') ?? false;
