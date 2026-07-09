// Anti-replay por épocas de sessão (sid/seq) — ver docs/protocolo.md §3.
// Precisa casar EXATAMENTE com a extensão (src/lib/replay.js).
//
// `sid` = epoch-ms amostrado 1x no início do processo remetente;
// `seq` = contador monotônico dentro do sid. Aceita se sid > lastSid
// (época nova) OU (sid == lastSid E seq > lastSeq). Rejeição NUNCA
// altera o estado. Puro (sem Firebase/IO) — testável (test/replay_test.dart).

/// Folga p/ relógio adiantado do remetente (e janela padrão p/ o passado).
const int kTsSkewMs = 120000;

class ReplayGuard {
  ReplayGuard({this.maxAgeMs = kTsSkewMs, int lastSid = 0, int lastSeq = 0})
      : _lastSid = lastSid,
        _lastSeq = lastSeq;

  /// Idade máxima aceita do `ts` (no passado). O futuro é sempre limitado
  /// a [kTsSkewMs]. Canal `cmd` usa 12h; `report`/`ack` usam o padrão.
  final int maxAgeMs;

  int _lastSid;
  int _lastSeq;

  int get lastSid => _lastSid;
  int get lastSeq => _lastSeq;

  /// Aceita e registra (sid, seq), ou rejeita sem alterar o estado.
  bool accept({
    required int sid,
    required int seq,
    required int ts,
    required int nowMs,
  }) {
    if (ts < nowMs - maxAgeMs) return false; // velho demais
    if (ts > nowMs + kTsSkewMs) return false; // futuro demais
    if (sid > _lastSid) {
      _lastSid = sid;
      _lastSeq = seq;
      return true;
    }
    if (sid == _lastSid && seq > _lastSeq) {
      _lastSeq = seq;
      return true;
    }
    return false;
  }

  /// Estado p/ persistência (espelho de `toJSON()` no JS).
  Map<String, int> toMap() => {'sid': _lastSid, 'seq': _lastSeq};

  static ReplayGuard fromMap(
    Map<dynamic, dynamic>? m, {
    int maxAgeMs = kTsSkewMs,
  }) {
    return ReplayGuard(
      maxAgeMs: maxAgeMs,
      lastSid: (m?['sid'] as num?)?.toInt() ?? 0,
      lastSeq: (m?['seq'] as num?)?.toInt() ?? 0,
    );
  }
}
