// Vetores do anti-replay (sid/seq) — MESMA tabela do espelho JS
// (chromebook-controller-extension/tests/replay.test.mjs). Se quebrar,
// os dois lados divergiram na aceitação de envelopes — ver protocolo.md §3.

import 'package:controle_de_aula/src/cloud/replay_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// Base de tempo fixa (epoch-ms) usada em todos os vetores.
const int t0 = 1767369600000;
const int hora = 3600000;

// [sid, seq, ts, nowMs, esperado] — aplicados EM ORDEM no mesmo guard.
const vetoresReport = [
  [1000, 1, t0, t0, true], // 1ª mensagem
  [1000, 2, t0, t0, true], // seq avança
  [1000, 2, t0, t0, false], // replay do mesmo seq
  [1000, 1, t0, t0, false], // replay de seq antigo
  [2000, 1, t0, t0, true], // época nova zera o contador
  [1000, 99, t0, t0, false], // época antiga rejeitada
  [2000, 3, t0 - 121000, t0, false], // ts velho demais (janela 120s)
  [2000, 3, t0 + 121000, t0, false], // ts futuro demais
  [2000, 3, t0 + 119000, t0, true], // folga de relógio ok (rejeições não mutaram)
  [2000, 4, t0 - 119000, t0, true], // dentro da janela p/ trás
];

// Canal cmd: janela de 12h p/ trás, folga padrão (120s) p/ frente.
const vetoresCmd = [
  [1000, 1, t0 - 11 * hora, t0, true], // comando de 11h atrás ainda vale
  [1000, 2, t0 - 13 * hora, t0, false], // 13h atrás = velho demais
  [1000, 2, t0, t0, true], // seq continua de onde parou
];

// Multi-remetente (workspace, app >= 0.15): cada celular manda sid NOVO por
// mensagem, amostrado do relógio do SERVIDOR (comum a todos) — o guard aceita
// a alternância porque o sid sempre cresce; replay segue rejeitado.
const vetoresMultiRemetente = [
  [t0 + 1, 1, t0 + 1, t0 + 2, true], // celular A
  [t0 + 5, 1, t0 + 5, t0 + 6, true], // celular B
  [t0 + 9, 1, t0 + 9, t0 + 10, true], // celular A de novo — não foi envenenado
  [t0 + 5, 1, t0 + 5, t0 + 11, false], // replay do envio do B
  [t0 + 3, 1, t0 + 3, t0 + 12, false], // mensagem atrasada de sid antigo morre
  [t0 + 20, 1, t0 + 20, t0 + 21, true], // fluxo segue
];

void main() {
  test('vetores do canal report/ack (janela padrão ±120s)', () {
    final g = ReplayGuard();
    for (var i = 0; i < vetoresReport.length; i++) {
      final v = vetoresReport[i];
      expect(
        g.accept(sid: v[0] as int, seq: v[1] as int, ts: v[2] as int, nowMs: v[3] as int),
        v[4],
        reason: 'vetor #${i + 1}',
      );
    }
  });

  test('vetores do canal cmd (janela 12h)', () {
    final g = ReplayGuard(maxAgeMs: 12 * hora);
    for (var i = 0; i < vetoresCmd.length; i++) {
      final v = vetoresCmd[i];
      expect(
        g.accept(sid: v[0] as int, seq: v[1] as int, ts: v[2] as int, nowMs: v[3] as int),
        v[4],
        reason: 'vetor #${i + 1}',
      );
    }
  });

  test('vetores multi-remetente (2 celulares, sid por mensagem)', () {
    final g = ReplayGuard(maxAgeMs: 12 * hora);
    for (var i = 0; i < vetoresMultiRemetente.length; i++) {
      final v = vetoresMultiRemetente[i];
      expect(
        g.accept(sid: v[0] as int, seq: v[1] as int, ts: v[2] as int, nowMs: v[3] as int),
        v[4],
        reason: 'vetor #${i + 1}',
      );
    }
  });

  test('persistência: toMap/fromMap preservam o estado', () {
    final g = ReplayGuard(maxAgeMs: 12 * hora);
    expect(g.accept(sid: 5000, seq: 7, ts: t0, nowMs: t0), true);
    final restaurado = ReplayGuard.fromMap(g.toMap(), maxAgeMs: 12 * hora);
    // Replay do mesmo (sid, seq) rejeitado após restaurar.
    expect(restaurado.accept(sid: 5000, seq: 7, ts: t0, nowMs: t0), false);
    expect(restaurado.accept(sid: 5000, seq: 8, ts: t0, nowMs: t0), true);
  });

  test('fromMap tolera nulo (estado inicial)', () {
    final g = ReplayGuard.fromMap(null);
    expect(g.accept(sid: 1, seq: 1, ts: t0, nowMs: t0), true);
  });
}
