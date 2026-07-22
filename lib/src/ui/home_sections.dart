// Seções da home (aba Aula): telão → minha aula → aulas de colegas →
// disponíveis → offline. Puro (sem widgets/Firebase) — home_sections_test.

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

  /// Só a seção Offline: escondida atrás de "Ver todos (+N offline)".
  final bool colapsavel;
}

List<SecaoHome> secoesDaHome(List<PcHome> pcs) {
  List<String> ordenar(Iterable<PcHome> xs) {
    final l = [...xs]..sort(
        (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
      );
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
    if (telao.isNotEmpty) SecaoHome(titulo: null, ids: ordenar(telao)),
    if (minha.isNotEmpty)
      SecaoHome(
        titulo: () {
          final turma = pcs.firstWhere((p) => p.aula?.minha ?? false).aula!.turma;
          return turma == null || turma.isEmpty
              ? 'Minha aula'
              : 'Minha aula — $turma';
        }(),
        ids: ordenar(minha),
      ),
    for (final prof in professores)
      SecaoHome(titulo: 'Aula de $prof', ids: ordenar(porProfessor[prof]!)),
    if (disponiveis.isNotEmpty)
      SecaoHome(titulo: 'Disponíveis', ids: ordenar(disponiveis)),
    if (offline.isNotEmpty)
      SecaoHome(titulo: 'Offline', ids: ordenar(offline), colapsavel: true),
  ];

  // Uma seção só (fora o telão) = lista flat sem header (zero ruído).
  final comConteudo = secoes.where((s) => s.titulo != null).toList();
  if (comConteudo.length <= 1) {
    return [
      for (final s in secoes)
        SecaoHome(titulo: null, ids: s.ids, colapsavel: s.colapsavel),
    ];
  }
  return secoes;
}
