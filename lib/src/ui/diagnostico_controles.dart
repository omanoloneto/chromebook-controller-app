// "Diagnóstico" nas ações do computador: liga a gravação de Wi-Fi, internet
// e tampa por algumas horas; enquanto o PC grava (meta/diag), o botão fica
// desabilitado e o ⋮ oferece "Parar o diagnóstico".

import 'package:flutter/material.dart';

import '../commands/command.dart' show kHorasDiagnostico;
import '../pairing/pairing_controller.dart';
import 'componentes.dart';

/// "14:05" para o prazo do diagnóstico.
String horaCurta(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void _snack(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

/// Pergunta e liga o diagnóstico por [kHorasDiagnostico] horas no PC.
Future<void> mostrarDiagnosticoDoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final gravar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Diagnóstico de Wi-Fi e da tampa'),
      content: const Text(
        'O computador grava a cada minuto o Wi-Fi, as redes à volta, a internet, '
        'a tampa e o que o sistema registra, também entre reinícios. Nunca '
        'senhas. Só o fundador da escola lê, pelo console do Firebase.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Gravar $kHorasDiagnostico horas'),
        ),
      ],
    ),
  );
  if (gravar != true || !context.mounted) return;
  final s = pairing.pcPorId(deviceId);
  final ligado = s != null && pairing.isOnline(s);
  final erro = await pairing.diagnosticoPc(deviceId, kHorasDiagnostico);
  if (!context.mounted) return;
  if (erro != null) {
    _snack(context, erro);
  } else if (!ligado) {
    _snack(
      context,
      '$nome está desligado: começa a gravar quando ligar, por $kHorasDiagnostico horas.',
    );
  } else {
    final ate = DateTime.now().add(const Duration(hours: kHorasDiagnostico));
    _snack(context, '$nome grava o diagnóstico até as ${horaCurta(ate)}.');
  }
}

/// Confirma e para a gravação no PC.
Future<void> pararDiagnosticoDoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final parar = await confirmar(
    context,
    titulo: 'Parar o diagnóstico',
    mensagem: '$nome para de gravar agora. O que já foi gravado continua no Firebase.',
    acao: 'Parar',
  );
  if (!parar || !context.mounted) return;
  final erro = await pairing.diagnosticoPc(deviceId, 0);
  if (!context.mounted) return;
  _snack(context, erro ?? '$nome para de gravar o diagnóstico.');
}
