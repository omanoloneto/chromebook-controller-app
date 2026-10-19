// Seções da home (aba Aula): telão → na aula → aulas de colegas →
// disponíveis → desligados. Puro (sem widgets/Firebase) — home_sections_test.

import '../util/natural_sort.dart';

/// O que a home precisa saber de cada PC para agrupar.
typedef PcHome = ({
  String id,
  String nome, // p/ ordenação alfabética dentro da seção
  bool online,
  bool telao,
  ({bool minha, String professor, String? turma})? aula,
});

class SecaoHome {
  const SecaoHome({required this.titulo, required this.ids, this.colapsavel = false});

  /// null = sem header (lista flat).
  final String? titulo;
  final List<String> ids;

  /// Só a seção Desligados: escondida atrás de "Mostrar N desligados".
  final bool colapsavel;
}

List<SecaoHome> secoesDaHome(List<PcHome> pcs) {
  List<String> ordenar(Iterable<PcHome> xs) {
    // Ordem natural: "Unidade 3" antes de "Unidade 12" (não 12 antes de 3).
    final l = [...xs]..sort((a, b) => compararNatural(a.nome, b.nome));
    return l.map((p) => p.id).toList();
  }

  final telao = pcs.where((p) => p.telao);
  final minha = pcs.where((p) => !p.telao && (p.aula?.minha ?? false));
  final colegas = pcs.where((p) => !p.telao && p.aula != null && !p.aula!.minha);
  final soltos = pcs.where((p) => !p.telao && p.aula == null);
  final disponiveis = soltos.where((p) => p.online);
  final offline = soltos.where((p) => !p.online);

  // Aulas de colegas: uma seção por professor, alfabético.
  final porProfessor = <String, List<PcHome>>{};
  for (final p in colegas) {
    porProfessor.putIfAbsent(p.aula!.professor, () => []).add(p);
  }
  final professores = porProfessor.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final secoes = <SecaoHome>[
    if (telao.isNotEmpty)
      SecaoHome(titulo: 'Computador do Professor', ids: ordenar(telao)),
    // A turma já está no alto da tela.
    if (minha.isNotEmpty) SecaoHome(titulo: 'Na aula', ids: ordenar(minha)),
    for (final prof in professores)
      SecaoHome(titulo: 'Aula de $prof', ids: ordenar(porProfessor[prof]!)),
    if (disponiveis.isNotEmpty)
      SecaoHome(titulo: 'Disponíveis', ids: ordenar(disponiveis)),
    if (offline.isNotEmpty)
      SecaoHome(titulo: 'Desligados', ids: ordenar(offline), colapsavel: true),
  ];

  // Uma seção só = lista sem título (zero ruído).
  final comConteudo = secoes.where((s) => s.titulo != null).toList();
  if (comConteudo.length <= 1) {
    return [
      for (final s in secoes)
        SecaoHome(titulo: null, ids: s.ids, colapsavel: s.colapsavel),
    ];
  }
  return secoes;
}
