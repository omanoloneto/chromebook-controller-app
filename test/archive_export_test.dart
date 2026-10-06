// Exportação do arquivo em planilha: CSV que o Excel em português abre direto,
// células que não viram fórmula e a leitura de vários PCs e dias.

import 'package:controle_de_aula/src/cloud/archive_export.dart';
import 'package:controle_de_aula/src/cloud/archive_store.dart';
import 'package:controle_de_aula/src/ui/exportar_historico.dart';
import 'package:flutter_test/flutter_test.dart';

/// [dia]/10/2026 às [hora]:[min]:[seg] em São Paulo (UTC−3).
int _sp(int hora, int min, [int seg = 0, int dia = 6]) =>
    DateTime.utc(2026, 10, dia, hora + 3, min, seg).millisecondsSinceEpoch;

ArchivedNavEvent _ev(int ts, String url, {String title = '', String? action}) =>
    ArchivedNavEvent(ts: ts, url: url, title: title, action: action);

ArchivedDay _dia(
  String user,
  int login,
  List<ArchivedNavEvent> events, {
  int unreadable = 0,
}) {
  final session = ArchivedSession(user: user, login: login)
    ..events.addAll(events);
  return ArchivedDay(sessions: [session], unreadable: unreadable);
}

const _vazio = ArchivedDay(sessions: [], unreadable: 0);

ExportRow _row(ArchivedNavEvent e, {int? unit = 3}) =>
    ExportRow(event: e, user: 'aluno', pc: 'PC 3', unit: unit);

/// Linhas sem o BOM.
List<String> _lines(String csv) => csv.substring(1).split('\r\n');

void main() {
  group('archiveCsv', () {
    test('BOM, ponto e vírgula, CRLF e hora da escola', () {
      final csv = archiveCsv([
        _row(_ev(_sp(13, 5, 9), 'https://www.youtube.com/', title: 'YouTube')),
      ]);
      expect(csv.startsWith('﻿'), isTrue);
      expect(csv.endsWith('\r\n'), isTrue);
      expect(_lines(csv).take(2), [
        'Data;Hora;Unidade;PC;Conta;Site;Endereço;Situação',
        '06/10/2026;13:05:09;3;PC 3;aluno;YouTube;https://www.youtube.com/;',
      ]);
    });

    test('situação do site e PC sem número', () {
      final lines = _lines(
        archiveCsv([
          _row(_ev(_sp(8, 0), 'https://tiktok.com/', action: 'bloqueado')),
          _row(
            _ev(_sp(8, 1), 'https://jogos.com/', action: 'alerta'),
            unit: null,
          ),
        ]),
      );
      expect(lines[1], endsWith(';Bloqueado'));
      expect(lines[2], startsWith('06/10/2026;08:01:00;;PC 3;'));
      expect(lines[2], endsWith(';Aviso'));
    });

    test('aspas, ponto e vírgula e quebra de linha ficam entre aspas', () {
      final csv = archiveCsv([
        _row(
          _ev(_sp(9, 0), 'https://a.com/?q=1;2', title: 'Diga "oi"\nagora'),
        ),
      ]);
      expect(csv, contains(';"Diga ""oi""\nagora";"https://a.com/?q=1;2";'));
    });

    test('título que viraria fórmula sai com apóstrofo', () {
      const casos = {
        '=HYPERLINK("http://mal.com")': '"\'=HYPERLINK(""http://mal.com"")"',
        '+1+1': "'+1+1",
        '-2': "'-2",
        '@SUM(A1)': "'@SUM(A1)",
        '=1;2': '"\'=1;2"',
      };
      casos.forEach((titulo, celula) {
        final csv = archiveCsv([
          _row(_ev(_sp(9, 0), 'https://a.com/', title: titulo)),
        ]);
        expect(csv, contains(';$celula;https://a.com/;'), reason: titulo);
      });
    });
  });

  group('collectArchive', () {
    ExportSource fonte(
      String name,
      int unit,
      Map<String, ArchivedDay> byDay,
      List<String> lidos,
    ) =>
        ExportSource(
          name: name,
          unit: unit,
          readDay: (day) async {
            lidos.add('$name $day');
            return byDay[day] ?? _vazio;
          },
        );

    test('junta os PCs em ordem de horário e soma o que não abriu', () async {
      final lidos = <String>[];
      final result = await collectArchive(
        [
          fonte(
            'PC 1',
            1,
            {
              '2026-10-06': _dia(
                'ana',
                _sp(7, 0),
                [
                  _ev(_sp(7, 30), 'https://b.com/'),
                  _ev(_sp(7, 10), 'https://a.com/'),
                ],
                unreadable: 1,
              ),
            },
            lidos,
          ),
          fonte(
            'PC 2',
            2,
            {
              '2026-10-05': _dia(
                'bia',
                _sp(9, 0, 0, 5),
                [_ev(_sp(9, 5, 0, 5), 'https://ontem.com/')],
              ),
              '2026-10-06': _dia(
                'bia',
                _sp(7, 0),
                [_ev(_sp(7, 20), 'https://c.com/')],
                unreadable: 2,
              ),
            },
            lidos,
          ),
        ],
        ['2026-10-05', '2026-10-06'],
      );
      expect(lidos, hasLength(4));
      expect(
        [for (final r in result.rows) '${r.pc} ${r.user} ${r.event.url}'],
        [
          'PC 2 bia https://ontem.com/',
          'PC 1 ana https://a.com/',
          'PC 2 bia https://c.com/',
          'PC 1 ana https://b.com/',
        ],
      );
      expect(result.rows.first.unit, 2);
      expect(result.unreadable, 3);
      expect(result.failed, isEmpty);
    });

    test('PC que falha não derruba os outros e aparece uma vez', () async {
      final result = await collectArchive(
        [
          ExportSource(
            name: 'Quebrado',
            readDay: (_) async => throw Exception('sem rede'),
          ),
          ExportSource(
            name: 'Bom',
            readDay: (_) async =>
                _dia('ana', _sp(7, 0), [_ev(_sp(7, 1), 'https://a.com/')]),
          ),
        ],
        ['2026-10-05', '2026-10-06'],
      );
      expect(result.failed, ['Quebrado']);
      // O mesmo lote nos dois dias (reenvio) entra uma vez só.
      expect(result.rows, hasLength(1));
    });

    test('progresso chega ao total, com leituras limitadas', () async {
      var abertas = 0;
      var pico = 0;
      final progresso = <int>[];
      await collectArchive(
        [
          for (var i = 0; i < 5; i++)
            ExportSource(
              name: 'PC $i',
              readDay: (_) async {
                abertas++;
                if (abertas > pico) pico = abertas;
                await Future<void>.delayed(const Duration(milliseconds: 5));
                abertas--;
                return _vazio;
              },
            ),
        ],
        recentDays(_sp(12, 0), count: 3),
        parallel: 4,
        onProgress: (done, total) {
          expect(total, 15);
          progresso.add(done);
        },
      );
      expect(progresso, [for (var i = 1; i <= 15; i++) i]);
      expect(pico, 4);
    });
  });

  test('nome do arquivo', () {
    expect(
      exportFileName(from: '2026-09-30', to: '2026-10-06'),
      'historico-todos-os-pcs-2026-09-30-a-2026-10-06.csv',
    );
    expect(
      exportFileName(from: '2026-10-06', to: '2026-10-06', unit: 12, pc: 'x'),
      'historico-unidade-12-2026-10-06.csv',
    );
    expect(
      exportFileName(
        from: '2026-10-05',
        to: '2026-10-06',
        pc: 'Laboratório Ção / 2',
      ),
      'historico-laboratorio-cao-2-2026-10-05-a-2026-10-06.csv',
    );
    expect(
      exportFileName(from: '2026-10-06', to: '2026-10-06', pc: '!!!'),
      'historico-pc-2026-10-06.csv',
    );
  });

  test('rótulo do período', () {
    expect(rotuloDoPeriodo(['2026-10-06']), 'Só hoje (06/10)');
    expect(
      rotuloDoPeriodo(recentDays(_sp(12, 0), count: 7)),
      'Últimos 7 dias (30/09 a 06/10)',
    );
  });
}
