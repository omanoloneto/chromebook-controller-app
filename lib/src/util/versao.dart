// Versões de um PC para exibição: a do agente (meta/ext) e a do sistema (meta/os).

/// "celita-0.10.0" → "0.10.0"; "0.4.11" → "0.4.11"; nula/vazia → null.
String? versaoCurta(String? ext) {
  var v = ext?.trim() ?? '';
  if (v.startsWith('celita-')) v = v.substring('celita-'.length);
  return v.isEmpty ? null : v;
}

/// O PC roda o Celita OS (o agente publica meta/ext = "celita-<versão>")?
bool temCelita(String? ext) => ext?.trim().startsWith('celita-') ?? false;

/// Compara versões numéricas ("1.9.0" < "1.10.0"). Partes não numéricas
/// valem 0.
int compararVersoes(String a, String b) {
  List<int> partes(String v) =>
      v.split(RegExp(r'[^0-9]+')).where((p) => p.isNotEmpty).map(int.parse).toList();
  final pa = partes(a), pb = partes(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// Versões mínimas dos recursos de turma (chat, pedidos, trava, prova, grade,
/// confirmação positiva) — docs/protocolo.md §8 "Recursos de turma".
const String kTurmaMinimoCelita = '0.13.0';
const String kTurmaMinimoExtensao = '0.7.0';

/// O PC entende os recursos de turma? `ext` = meta/ext: "celita-<versão do
/// pacote>" no Celita OS, a versão da extensão no ChromeOS. Nula ou vazia =
/// não sabemos = trata como antigo.
bool suportaTurma(String? ext) {
  final v = ext?.trim() ?? '';
  if (v.isEmpty) return false;
  if (v.startsWith('celita-')) {
    final pacote = v.substring('celita-'.length);
    if (pacote.isEmpty) return false;
    return compararVersoes(pacote, kTurmaMinimoCelita) >= 0;
  }
  return compararVersoes(v, kTurmaMinimoExtensao) >= 0;
}

/// PC com Celita mais velho que a versão publicada. Agente que não publica a
/// versão do sistema (meta/os) é de antes da 1.24.0, então está velho.
bool celitaDesatualizado(String? os, String? ext, String? maisNova) {
  if (maisNova == null || !temCelita(ext)) return false;
  if (os == null) return true;
  return compararVersoes(os, maisNova) < 0;
}

/// Nome do PC nas listas: o nome salvo + " (versão do Celita OS)"; nunca é
/// gravado como nome.
String nomeComVersao(String nome, String? os, {bool desatualizado = false}) {
  final partes = [if (os != null && os.isNotEmpty) os, if (desatualizado) 'desatualizado'];
  return partes.isEmpty ? nome : '$nome (${partes.join(' · ')})';
}
