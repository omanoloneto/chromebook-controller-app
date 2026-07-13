// Alvo dos comandos de turma (abrir URL, fechar site/tudo, encerrar aula).
// Regra: durante aula ativa, só PCs vinculados a algum aluno; fora de aula,
// todos os pareados. O PC do professor (telão) NUNCA é alvo de broadcast.
// Puro (sem Firebase) — testável em broadcast_target_test.dart.

/// [vinculados] = deviceIds com aluno vinculado (chaves de session.vinculos).
/// [todos] = todos os deviceIds pareados no registry.
List<String> alvoDeBroadcast({
  required bool aulaAtiva,
  required Iterable<String> vinculados,
  required Iterable<String> todos,
  String? pcProfessorId,
}) {
  final base = aulaAtiva ? vinculados : todos;
  return base.where((id) => id != pcProfessorId).toList();
}
