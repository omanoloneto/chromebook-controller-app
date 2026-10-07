// Fotos e vídeos da Câmera: o app abre o índice e as partes midia-v1 que o
// agente do Celita gera (vetor tirado do código Python), recusa parte fora de
// lugar e formata tamanho e duração.

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/cloud/media_store.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/ui/media_page.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String h) => [
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ];

final Map<String, dynamic> _vetor =
    jsonDecode(File('test/fixtures/midia-v1.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final crypto = SessionCrypto(_hex(_vetor['key'] as String));
  final mid = _vetor['mid'] as String;
  final r = _vetor['r'] as String;

  test('índice do agente abre e vira item', () async {
    final itens = await parseIndice(
      {
        mid: {'env': _vetor['env'], 'ts': 1},
        'outroXXXXXXXXXXX': {'env': 'lixo', 'ts': 1},
        'semEnvXXXXXXXXXX': {'ts': 1},
      },
      crypto,
    );
    expect(itens, hasLength(1));
    final item = itens.single;
    expect(item.mid, mid);
    expect(item.video, isTrue);
    expect(item.nome, 'Vídeo 2026-10-07 10.01.00.mp4');
    expect(item.conta, 'aluno');
    expect(item.guardado, isTrue);
    expect(item.expira, item.ts + 15 * 24 * 60 * 60 * 1000);
    expect(item.duracao, 3.5);
    expect(item.thumb, isNotNull);
  });

  test('item com chave trocada não entra', () async {
    final itens = await parseIndice(
      {
        'XXXXXXXXXXXXXXXX': {'env': _vetor['env'], 'ts': 1},
      },
      crypto,
    );
    expect(itens, isEmpty);
  });

  test('partes do agente abrem na ordem e recusam troca de lugar', () async {
    final partes = [for (final p in _vetor['partes'] as List) _hex(p as String)];
    final dados = <int>[];
    for (var n = 0; n < partes.length; n++) {
      dados.addAll(await crypto.openPart(partes[n], aadDaParte(mid, r, n, 2)));
    }
    expect(utf8.decode(dados), 'ola mundo');
    await expectLater(
      crypto.openPart(partes[1], aadDaParte(mid, r, 0, 2)),
      throwsA(anything),
    );
    await expectLater(
      crypto.openPart(partes[0], aadDaParte(mid, 'S' * 22, 0, 2)),
      throwsA(anything),
    );
  });

  test('envio do PC: caminho das partes e campos validados', () {
    final envio = EnvioMidia.fromMap({'u': 'uid-pc', 'r': r, 'partes': 3, 'prontas': 9, 'bytes': 10});
    expect(envio, isNotNull);
    expect(envio!.prontas, 3, reason: 'nunca mais prontas que partes');
    expect(envio.caminho(mid, 2), 'midia/uid-pc/$mid/${r}_2.bin');
    expect(EnvioMidia.fromMap({'u': '../x', 'r': r, 'partes': 1, 'prontas': 0, 'bytes': 1}), isNull);
    expect(EnvioMidia.fromMap({'u': 'uid', 'r': 'curto', 'partes': 1, 'prontas': 0, 'bytes': 1}), isNull);
    expect(EnvioMidia.fromMap({'u': 'uid', 'r': r, 'partes': 0, 'prontas': 0, 'bytes': 1}), isNull);
  });

  test('tamanho e duração legíveis', () {
    expect(tamanhoLegivel(850 * 1024), '850 KB');
    expect(tamanhoLegivel(12900000), '12,3 MB');
    expect(tamanhoLegivel(1288490189), '1,2 GB');
    expect(duracaoLegivel(42.4), '0:42');
    expect(duracaoLegivel(725), '12:05');
    expect(duracaoLegivel(3723), '1:02:03');
  });
}
