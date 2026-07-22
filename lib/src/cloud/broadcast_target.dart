// Alvo dos comandos de turma (abrir URL, fechar site/tudo, encerrar aula).
// Regra: durante aula ativa, só PCs vinculados a algum aluno; fora de aula,
// todos os pareados MENOS os presos na aula de outro professor (workspace —
// o professor ocioso não invade a aula do colega). O PC do professor (telão)
// NUNCA é alvo de broadcast. Puro (sem Firebase) — testável.

/// [vinculados] = deviceIds com aluno vinculado (chaves de session.vinculos).
/// [todos] = todos os deviceIds pareados no registry.
/// [travadosPorOutros] = PCs na aula de OUTRO professor (aula_locks).
List<String> alvoDeBroadcast({
  required bool aulaAtiva,
  required Iterable<String> vinculados,
  required Iterable<String> todos,
  String? pcProfessorId,
  Set<String> travadosPorOutros = const {},
}) {
  final base = aulaAtiva ? vinculados : todos;
  return base
      .where((id) => id != pcProfessorId && !travadosPorOutros.contains(id))
      .toList();
}
