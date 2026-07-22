// Travas de aula: decisão pura de expiração (o resto é Firebase, coberto
// pelas rules no emulador — tests/rules-school.test.mjs na extensão).

import 'package:controle_de_aula/src/cloud/aula_locks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t0 = 1767369600000;

  test('trava fresca não expira; >15min sem heartbeat expira', () {
    expect(travaExpirada(ts: t0, agoraMs: t0 + 1), false);
    expect(travaExpirada(ts: t0, agoraMs: t0 + 14 * 60000), false);
    expect(travaExpirada(ts: t0, agoraMs: t0 + 15 * 60000), false); // limite
    expect(travaExpirada(ts: t0, agoraMs: t0 + 15 * 60000 + 1), true);
  });

  test('janela espelha as rules (900000 ms)', () {
    expect(kTravaExpira.inMilliseconds, 900000);
  });
}
