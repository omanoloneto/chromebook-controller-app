// Transporte via Firebase RTDB (protocolo v4) — substitui o ControlServer.
// O app escuta o roster (/teachers/{uid}/devices) e, por PC, os nós report/
// presence/ack/bind. Comandos saem selados (AES-256-GCM, cabeçalho
// {sid,seq,ts}) para cmd/ (fila) ou state/ (snapshot). Ver docs/protocolo.md.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../commands/command.dart';
import '../secure/keypair.dart';
import 'qr_payload.dart';
import 'session_registry.dart';

class FirebaseTransport {
  FirebaseTransport({
    required this.teacher,
    required this.teacherUid,
    this.teacherName = 'Professor',
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final DeviceKeyPair teacher;
  final String teacherUid;
  final String teacherName;
  final FirebaseDatabase _db;

  final SessionRegistry registry = SessionRegistry();

  /// Chamado ao (re)parear um PC — devolve os comandos de estado vigentes
  /// PARA AQUELE PC (set_rules sempre — pode variar por liberações da aula;
  /// set_wallpaper se houver). Injetado pelo controller.
  List<Map<String, dynamic>> Function(String deviceId)? comandosDeEstado;

  // Época de sessão (anti-replay): amostrada 1x por vida do processo.
  final int _sid = DateTime.now().millisecondsSinceEpoch;
  final Map<String, int> _outSeq = {}; // por deviceId

  int _serverOffsetMs = 0;
  StreamSubscription<DatabaseEvent>? _offsetSub;
  StreamSubscription<DatabaseEvent>? _rosterSub;
  final Map<String, List<StreamSubscription<DatabaseEvent>>> _deviceSubs = {};
  final Map<String, bool> _primeiroReport = {};

  /// Agora na base de tempo do SERVIDOR (p/ comparar com presence.lastSeen).
  DateTime nowServer() => DateTime.now().add(Duration(milliseconds: _serverOffsetMs));

  DatabaseReference _dev(String deviceId) => _db.ref('devices/$deviceId');

  Future<void> start() async {
    _offsetSub = _db.ref('.info/serverTimeOffset').onValue.listen((e) {
      _serverOffsetMs = (e.snapshot.value as num?)?.toInt() ?? 0;
    });
    // Roster: sincroniza o conjunto de PCs pareados.
    _rosterSub = _db.ref('teachers/$teacherUid/devices').onValue.listen((e) {
      final ids = <String>{};
      final v = e.snapshot.value;
      if (v is Map) {
        for (final k in v.keys) {
          ids.add(k.toString());
        }
      }
      for (final id in ids) {
        if (!_deviceSubs.containsKey(id)) _attach(id);
      }
      for (final id in _deviceSubs.keys.toList()) {
        if (!ids.contains(id)) _detach(id, removerSessao: true);
      }
    });
  }

  Future<void> stop() async {
    await _offsetSub?.cancel();
    await _rosterSub?.cancel();
    for (final id in _deviceSubs.keys.toList()) {
      _detach(id);
    }
  }

  // ---- Pareamento -----------------------------------------------------------------

  /// Passo do professor no fluxo do QR: grava o bind (as rules validam token +
  /// TOFU), o roster e o estado vigente. Lança [FirebaseException]
  /// (permission-denied) se o QR expirou ou o PC pertence a outro professor.
  Future<void> pairDevice(QrPairPayload qr) async {
    final sessionKey = await teacher.deriveSessionKey(pubFromB64url(qr.pub));
    await _dev(qr.deviceId).child('bind').set({
      'teacherUid': teacherUid,
      'teacherPub': pubToB64url(teacher.publicBytes),
      'teacherName': teacherName,
      'token': qr.token,
      'ts': ServerValue.timestamp,
    });
    await _db.ref('teachers/$teacherUid/devices/${qr.deviceId}').set(true);

    registry.bind(deviceId: qr.deviceId, label: qr.label, sessionKey: sessionKey);
    if (!_deviceSubs.containsKey(qr.deviceId)) _attach(qr.deviceId);

    // Estado vigente (regras/wallpaper) — o PC atrasado lê state/* ao conectar.
    for (final cmd in comandosDeEstado?.call(qr.deviceId) ?? const []) {
      await setStateOne(qr.deviceId, cmd);
    }
  }

  /// "Esquecer PC": desfaz o vínculo no banco; a extensão detecta e volta ao QR.
  Future<void> forgetDevice(String deviceId) async {
    _detach(deviceId, removerSessao: true);
    await _dev(deviceId).child('bind').remove();
    await _db.ref('teachers/$teacherUid/devices/$deviceId').remove();
  }

  // ---- Listeners por PC --------------------------------------------------------------

  Future<void> _attach(String deviceId) async {
    _deviceSubs[deviceId] = []; // reserva antes dos awaits (evita attach duplo)
    _primeiroReport[deviceId] = true;

    // Sessão pode não existir ainda (app reaberto): rehidrata do meta/.
    if (registry.byId(deviceId) == null) {
      try {
        final meta = (await _dev(deviceId).child('meta').get()).value;
        if (meta is! Map) return _detach(deviceId);
        final pub = meta['pub'];
        if (pub is! String) return _detach(deviceId);
        final sessionKey = await teacher.deriveSessionKey(pubFromB64url(pub));
        registry.bind(
          deviceId: deviceId,
          label: (meta['label'] as String?) ?? 'Chromebook',
          sessionKey: sessionKey,
        );
      } catch (e) {
        debugPrint('[CdA] rehidratação de $deviceId falhou: $e');
        return _detach(deviceId);
      }
    }

    final subs = _deviceSubs[deviceId];
    if (subs == null) return; // detach durante os awaits

    subs.addAll([
      _dev(deviceId).child('presence/lastSeen').onValue.listen((e) {
        final ms = (e.snapshot.value as num?)?.toInt();
        if (ms != null) registry.touchServerTs(deviceId, ms);
      }),
      _dev(deviceId).child('report').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is Map) _onReport(deviceId, v);
      }),
      _dev(deviceId).child('ack').onChildAdded.listen((e) {
        final env = e.snapshot.value;
        if (env is String) _onAck(deviceId, e.snapshot.key!, env);
      }),
      _dev(deviceId).child('bind').onValue.listen((e) {
        // Bind sumiu = aluno desvinculou pelo popup: limpa roster e sessão.
        if (e.snapshot.value == null) {
          _detach(deviceId, removerSessao: true);
          _db.ref('teachers/$teacherUid/devices/$deviceId').remove();
        }
      }),
      _dev(deviceId).child('meta/label').onValue.listen((e) {
        final label = e.snapshot.value;
        final s = registry.byId(deviceId);
        if (label is String && label.isNotEmpty && s != null && s.label != label) {
          s.label = label;
          registry.onChange?.call();
        }
      }),
    ]);
  }

  void _detach(String deviceId, {bool removerSessao = false}) {
    final subs = _deviceSubs.remove(deviceId);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _primeiroReport.remove(deviceId);
    if (removerSessao) registry.remove(deviceId);
  }

  Future<void> _onReport(String deviceId, Map<dynamic, dynamic> node) async {
    final s = registry.byId(deviceId);
    final env = node['env'];
    if (s == null || env is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = await s.crypto.open(env);
    } catch (_) {
      return; // ilegível (raça de re-pareamento) — ignora
    }
    // 1ª leitura após abrir o app pode ser antiga (repousa no banco): aceita
    // sem janela de ts; ao vivo vale ±120s. sid/seq valem sempre.
    final primeira = _primeiroReport[deviceId] ?? true;
    _primeiroReport[deviceId] = false;
    final agora = DateTime.now().millisecondsSinceEpoch;
    final ok = s.reportGuard.accept(
      sid: (msg['sid'] as num?)?.toInt() ?? 0,
      seq: (msg['seq'] as num?)?.toInt() ?? 0,
      ts: primeira ? agora : (msg['ts'] as num?)?.toInt() ?? 0,
      nowMs: agora,
    );
    if (!ok) return;
    final report = TabReport.fromMap(msg);
    if (report == null) return;
    final serverTs = (node['ts'] as num?)?.toInt();
    registry.applyReport(
      deviceId,
      report,
      reportAt: serverTs != null ? DateTime.fromMillisecondsSinceEpoch(serverTs) : null,
    );
  }

  Future<void> _onAck(String deviceId, String pushId, String env) async {
    final s = registry.byId(deviceId);
    if (s == null) return;
    try {
      final msg = await s.crypto.open(env);
      final agora = DateTime.now().millisecondsSinceEpoch;
      final ok = s.ackGuard.accept(
        sid: (msg['sid'] as num?)?.toInt() ?? 0,
        seq: (msg['seq'] as num?)?.toInt() ?? 0,
        ts: (msg['ts'] as num?)?.toInt() ?? agora,
        nowMs: agora,
      );
      if (ok) {
        final ack = Ack.fromMap(msg);
        if (ack != null && !ack.ok) {
          debugPrint('[CdA] ack com erro de $deviceId: ${ack.error} (${ack.id})');
        }
      }
    } catch (_) {
      // ilegível — só consome
    }
    await _dev(deviceId).child('ack/$pushId').remove().catchError((_) {});
  }

  // ---- Saída (comandos) -----------------------------------------------------------

  Future<String> _sealFor(PcSession s, Map<String, dynamic> cmd) {
    final seq = (_outSeq[s.deviceId] ?? 0) + 1;
    _outSeq[s.deviceId] = seq;
    return s.crypto.seal({
      'sid': _sid,
      'seq': seq,
      'ts': DateTime.now().millisecondsSinceEpoch,
      ...cmd,
    });
  }

  /// Enfileira um comando one-shot (open_url, close_tabs) para um PC.
  Future<void> sendCommand(String deviceId, Map<String, dynamic> cmd) async {
    final s = registry.byId(deviceId);
    if (s == null) return;
    final env = await _sealFor(s, cmd);
    await _dev(deviceId).child('cmd').push().set(env);
  }

  /// Turma toda (envelopes diferem: cada sessão tem sua chave).
  Future<void> sendToAll(Map<String, dynamic> cmd) async {
    for (final s in registry.all) {
      await sendCommand(s.deviceId, cmd);
    }
  }

  /// Comando de estado: sobrescreve state/rules ou state/wallpaper.
  Future<void> setStateOne(String deviceId, Map<String, dynamic> cmd) async {
    final s = registry.byId(deviceId);
    if (s == null) return;
    final kind = cmd['type'] == MessageType.setWallpaper ? 'wallpaper' : 'rules';
    final env = await _sealFor(s, cmd);
    await _dev(deviceId).child('state/$kind').set(env);
  }

  Future<void> setStateAll(Map<String, dynamic> cmd) async {
    for (final s in registry.all) {
      await setStateOne(s.deviceId, cmd);
    }
  }

  /// Publica o blob do papel de parede (1x, compartilhado pela turma).
  /// O comando set_wallpaper (só o hash) vai por setStateAll.
  Future<void> publishWallpaper(Uint8List bytes, String hash) async {
    await _db.ref('wallpapers/$teacherUid').set({
      'hash': hash,
      'jpeg': base64Encode(bytes),
      'ts': ServerValue.timestamp,
    });
  }
}
