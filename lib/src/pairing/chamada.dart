// Chamada no início da aula: o professor marca quem veio e diz em qual
// unidade o aluno sentou. A presença é o vínculo aluno↔PC da aula.

/// Motivo para não pôr um aluno na unidade digitada, ou null se pode.
/// [deviceId] é o PC pareado com aquele número (null = nenhum).
String? motivoContraUnidade(
  int? numero, {
  required String? deviceId,
  required bool ehTelao,
}) {
  if (numero == null || numero < 1 || numero > 9999) {
    return 'Digite um número de 1 a 9999.';
  }
  if (deviceId == null) return 'Nenhum PC é a unidade $numero.';
  if (ehTelao) return 'A unidade $numero é o telão.';
  return null;
}
