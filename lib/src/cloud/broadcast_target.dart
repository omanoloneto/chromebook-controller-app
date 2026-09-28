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

/// Regras mudaram em OUTRO celular: quem editou já mandou o snapshot aos PCs
/// livres. Aqui só reenvia para os PCs em que este celular tem trava ou
/// liberação própria ([meus]) — o snapshot daqui leva as liberações daqui.
List<String> alvoDeRegrasRemotas({
  required Iterable<String> todos,
  required Set<String> meus,
  Set<String> travadosPorOutros = const {},
}) {
  return todos
      .where((id) => meus.contains(id) && !travadosPorOutros.contains(id))
      .toList();
}
