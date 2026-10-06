// Exportar o histórico guardado (até 15 dias) numa planilha, de um PC ou de
// todos, pelo compartilhar do Android (Drive, WhatsApp, e-mail...).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../cloud/archive_export.dart';
import '../cloud/archive_store.dart';
import '../pairing/pairing_controller.dart';
import 'device_page.dart';

String _diaMes(String dia) => '${dia.substring(8, 10)}/${dia.substring(5, 7)}';

/// "Últimos 7 dias (30/09 a 06/10)"; [dias] do mais novo para o mais velho.
String rotuloDoPeriodo(List<String> dias) => dias.length == 1
    ? 'Só hoje (${_diaMes(dias.first)})'
    : 'Últimos ${dias.length} dias '
        '(${_diaMes(dias.last)} a ${_diaMes(dias.first)})';

/// Escolhe quantos dias, lê o arquivo e abre o compartilhar com a planilha.
/// Sem [deviceId], exporta todos os PCs.
Future<void> exportarHistorico(
  BuildContext context,
  PairingController pairing, {
  String? deviceId,
}) async {
  final agora = pairing.agoraServidorMs();
  final quantos = await _escolherDias(context, agora, umPc: deviceId != null);
  if (quantos == null || !context.mounted) return;
  // Do mais velho para o mais novo: a planilha sai em ordem de horário.
  final dias = recentDays(agora, count: quantos).reversed.toList();
  final pcs = deviceId == null
      ? pairing.pcs
      : [if (pairing.pcPorId(deviceId) case final s?) s];
  final fontes = [
    for (final s in pcs)
      if (pairing.arquivoDe(s.deviceId) case final arquivo?)
        ExportSource(
          name: pairing.nomeDe(s),
          unit: pairing.numeroDe(s.deviceId),
          readDay: arquivo.readDay,
        ),
  ];
  final messenger = ScaffoldMessenger.of(context);
  void avisar(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  if (fontes.isEmpty) {
    avisar('Nenhum PC conectado para exportar.');
    return;
  }

  final progresso = ValueNotifier('Lendo o histórico…');
  final resultado = await esperarComSpinner(
    context,
    'Lendo o histórico…',
    collectArchive(
      fontes,
      dias,
      onProgress: (feitos, total) =>
          progresso.value = 'Lendo o histórico… ${feitos * 100 ~/ total}%',
    ),
    progresso: progresso,
  );
  if (!context.mounted || !continuaNaFrente(context)) return;
  if (resultado.rows.isEmpty) {
    avisar(
      resultado.failed.isNotEmpty
          ? 'Não deu para ler o histórico. Confira a internet do celular e '
              'tente de novo.'
          : 'Nenhum site visitado nesses dias.',
    );
    return;
  }

  final umPc = deviceId != null ? fontes.single : null;
  final nome = exportFileName(
    from: dias.first,
    to: dias.last,
    unit: umPc?.unit,
    pc: umPc?.name,
  );
  Directory? pasta;
  try {
    pasta = Directory('${(await getTemporaryDirectory()).path}/exportacoes');
    if (await pasta.exists()) await pasta.delete(recursive: true);
    await pasta.create(recursive: true);
    final arquivo = File('${pasta.path}/$nome');
    await arquivo.writeAsString(archiveCsv(resultado.rows), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(arquivo.path, mimeType: 'text/csv')],
        subject: umPc == null
            ? 'Histórico de todos os PCs'
            : 'Histórico — ${umPc.name}',
      ),
    );
  } catch (_) {
    avisar('Não deu para criar a planilha.');
    return;
  } finally {
    // O compartilhar já copiou o arquivo para a pasta dele: o histórico
    // decifrado não fica sobrando aqui.
    try {
      if (pasta != null && await pasta.exists()) {
        await pasta.delete(recursive: true);
      }
    } catch (_) {}
  }
  final avisos = [
    if (resultado.failed.isNotEmpty)
      'Ficou de fora o que não deu para ler de: ${resultado.failed.join(', ')}.',
    if (resultado.unreadable > 0) 'Parte do histórico não pôde ser aberta.',
  ];
  if (avisos.isNotEmpty) avisar(avisos.join(' '));
}

Future<int?> _escolherDias(
  BuildContext context,
  int agora, {
  required bool umPc,
}) {
  var quantos = 7;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          umPc
              ? 'Exportar o histórico deste PC'
              : 'Exportar o histórico de todos os PCs',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotuloDoPeriodo(recentDays(agora, count: quantos))),
            Slider(
              value: quantos.toDouble(),
              min: 1,
              max: kArchiveDays.toDouble(),
              divisions: kArchiveDays - 1,
              label: '$quantos',
              onChanged: (v) => setState(() => quantos = v.round()),
            ),
            Text(
              'O histórico fica guardado por $kArchiveDays dias. A planilha '
              'sai sem criptografia: guarde-a com cuidado.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, quantos),
            child: const Text('Exportar'),
          ),
        ],
      ),
    ),
  );
}
