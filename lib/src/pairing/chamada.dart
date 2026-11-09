// Chamada no início da aula: o professor marca quem veio e, se quiser, diz
// em qual computador o aluno sentou. A presença vale sozinha; o vínculo
// aluno↔PC é o que leva os comandos da turma até o computador.

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

/// Motivo para não pôr um aluno num PC escolhido na lista, ou null se pode.
String? motivoContraPc({
  required bool conectado,
  required bool ehTelao,
  required String? aulaDeOutro,
}) {
  if (!conectado) return 'Este PC não está mais conectado.';
  if (ehTelao) return 'Esse PC é o telão.';
  if (aulaDeOutro != null) return 'Esse PC está na aula de $aulaDeOutro.';
  return null;
}

/// O que o professor escolheu na folha de presença.
sealed class EscolhaPresenca {
  const EscolhaPresenca();
}

/// Veio, mas sem computador (ou o PC dele não está na lista).
class PresencaSemPc extends EscolhaPresenca {
  const PresencaSemPc();
}

/// Sentou na unidade de número [numero].
class PresencaNaUnidade extends EscolhaPresenca {
  const PresencaNaUnidade(this.numero);
  final int numero;
}

/// Sentou no PC [deviceId], escolhido na lista.
class PresencaNoPc extends EscolhaPresenca {
  const PresencaNoPc(this.deviceId);
  final String deviceId;
}
