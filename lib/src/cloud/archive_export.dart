// Exportação do arquivo de 15 dias numa planilha: o CSV que o Excel em
// português e o Planilhas Google abrem direto (UTF-8 com BOM, ";" e CRLF).
//
// Puro e testável sem Firebase: cada PC entra com a própria leitura de dia.

import 'dart:math';

import 'archive_store.dart';

/// Um site visitado, com o PC e a conta em que aconteceu.
class ExportRow {
  const ExportRow({
    required this.event,
    required this.user,
    required this.pc,
    this.unit,
  });

  final ArchivedNavEvent event;
  final String user;
  final String pc;
  final int? unit;
}

/// Um PC a exportar: nome, número da unidade e a leitura de um dia do arquivo
/// dele (decifrado com a chave do próprio PC).
class ExportSource {
  const ExportSource({required this.name, required this.readDay, this.unit});

  final String name;
  final int? unit;
  final Future<ArchivedDay> Function(String day) readDay;
}

class ExportResult {
  const ExportResult({
    required this.rows,
    required this.unreadable,
    required this.failed,
  });

  /// Em ordem de horário.
  final List<ExportRow> rows;

  /// Lotes que não abriram (somados de todos os PCs e dias).
  final int unreadable;

  /// Nomes dos PCs com algum dia que não deu para ler.
  final List<String> failed;
}

/// Lê [days] de cada PC, com no máximo [parallel] leituras ao mesmo tempo.
/// Um PC que falha não derruba os outros: entra em [ExportResult.failed].
Future<ExportResult> collectArchive(
  List<ExportSource> sources,
  List<String> days, {
  int parallel = 6,
  void Function(int done, int total)? onProgress,
}) async {
  final tasks = [
    for (var i = 0; i < sources.length; i++)
      for (final day in days) (i, day),
  ];
  final rows = <ExportRow>[];
  final seen = <String>{};
  final failed = <ExportSource>{};
  var unreadable = 0;
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (next < tasks.length) {
      final (index, day) = tasks[next++];
      final source = sources[index];
      try {
        final archived = await source.readDay(day);
        unreadable += archived.unreadable;
        for (final session in archived.sessions) {
          for (final e in session.events) {
            // Lote reenviado depois da meia-noite cai no dia seguinte também.
            final key =
                '$index|${session.login}|${session.user}|${e.ts}|${e.url}';
            if (!seen.add(key)) continue;
            rows.add(
              ExportRow(
                event: e,
                user: session.user,
                pc: source.name,
                unit: source.unit,
              ),
            );
          }
        }
      } catch (_) {
        failed.add(source);
      }
      onProgress?.call(++done, tasks.length);
    }
  }

  await Future.wait([
    for (var i = 0; i < min(parallel, tasks.length); i++) worker(),
  ]);
  rows.sort((a, b) {
    final byTime = a.event.ts.compareTo(b.event.ts);
    if (byTime != 0) return byTime;
    final byPc = a.pc.compareTo(b.pc);
    return byPc != 0 ? byPc : a.event.url.compareTo(b.event.url);
  });
  return ExportResult(
    rows: rows,
    unreadable: unreadable,
    failed: [for (final s in failed) s.name],
  );
}

const List<String> _header = [
  'Data',
  'Hora',
  'Unidade',
  'PC',
  'Conta',
  'Site',
  'Endereço',
  'Situação',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Planilha dos sites, uma linha por visita, na hora da escola.
String archiveCsv(Iterable<ExportRow> rows) {
  final out = StringBuffer('﻿');
  void line(List<String> cells) {
    out
      ..write(cells.map(_cell).join(';'))
      ..write('\r\n');
  }

  line(_header);
  for (final r in rows) {
    final t = schoolTime(r.event.ts);
    line([
      '${_two(t.day)}/${_two(t.month)}/${t.year}',
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
      r.unit?.toString() ?? '',
      r.pc,
      r.user,
      r.event.title,
      r.event.url,
      switch (r.event.action) {
        'bloqueado' => 'Bloqueado',
        'alerta' => 'Aviso',
        _ => '',
      },
    ]);
  }
  return out.toString();
}

// O título da página quem escolhe é o site: texto começando com = + - @ viraria
// fórmula ao abrir a planilha, então sai com apóstrofo na frente.
String _cell(String value) {
  var s = value;
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp('[";\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

const Map<String, String> _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String _slug(String text) {
  final plain = text
      .toLowerCase()
      .split('')
      .map((c) => _accents[c] ?? c)
      .join()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return plain.isEmpty ? 'pc' : plain;
}

/// "historico-todos-os-pcs-2026-09-30-a-2026-10-06.csv"; com [unit] ou [pc],
/// o do PC. [from] e [to] são dias AAAA-MM-DD.
String exportFileName({
  required String from,
  required String to,
  int? unit,
  String? pc,
}) {
  final who = unit != null
      ? 'unidade-$unit'
      : pc != null
          ? _slug(pc)
          : 'todos-os-pcs';
  final period = from == to ? from : '$from-a-$to';
  return 'historico-$who-$period.csv';
}
