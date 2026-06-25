// Servidor HTTP local do celular (multi-cliente) — ver docs/protocolo.md.
// O celular abre uma porta FIXA na LAN; cada Chromebook se descobre, faz /bind
// (X25519) e depois short-poll cifrado (AES-256-GCM por sessão).
//
// Rotas:
//   GET  /        -> banner em claro { app, v, name, teacherPub }
//   POST /bind    -> { devicePub, deviceId, label }; deriva sessão; resp { ok, teacherPub }
//   POST /poll?id -> envelope cifrado; responde comando ou pong
//   POST /ack?id  -> envelope cifrado do ACK

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../secure/keypair.dart';
import 'lan.dart';
import 'session_registry.dart';

const int kProtocolVersion = 3;
const int kFixedPort = 47615;

class ControlServer {
  ControlServer({required this.teacher, this.deviceName = 'Professor'});

  final DeviceKeyPair teacher;
  final String deviceName;
  final SessionRegistry registry = SessionRegistry();

  HttpServer? _server;
  String? ip;
  int port = kFixedPort;

  static const int _tsWindowMs = 120000;

  Future<void> start() async {
    ip = await descobrirIpLan();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, kFixedPort);
    port = _server!.port;
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ---- HTTP -----------------------------------------------------------------

  void _cors(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }

  Future<void> _handle(HttpRequest req) async {
    _cors(req.response);
    try {
      if (req.method == 'OPTIONS') {
        req.response.statusCode = 204;
        await req.response.close();
        return;
      }
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        await _banner(req);
        return;
      }
      if (req.method == 'POST' && path == '/bind') {
        await _onBind(req);
        return;
      }
      if (req.method == 'POST' && path == '/poll') {
        await _onPoll(req);
        return;
      }
      if (req.method == 'POST' && path == '/ack') {
        await _onAck(req);
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = 400;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _banner(HttpRequest req) async {
    final body = jsonEncode({
      'app': 'controle-de-aula',
      'v': kProtocolVersion,
      'name': deviceName,
      'teacherPub': pubToB64url(teacher.publicBytes),
    });
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body);
    await req.response.close();
  }

  Future<void> _onBind(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final devicePub = m['devicePub'];
    final deviceId = m['deviceId'];
    final label = (m['label'] as String?) ?? 'Chromebook';
    if (devicePub is! String || deviceId is! String) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final sessionKey = await teacher.deriveSessionKey(pubFromB64url(devicePub));
    registry.bind(deviceId: deviceId, label: label, sessionKey: sessionKey);

    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(
          <String, dynamic>{
            'ok': true,
            'teacherPub': pubToB64url(teacher.publicBytes),
          },
        ),
      );
    await req.response.close();
  }

  PcSession? _session(HttpRequest req) =>
      registry.byId(req.uri.queryParameters['id'] ?? '');

  // Decifra o corpo de poll/ack e aplica anti-replay. Null se inválido.
  Future<Map<String, dynamic>?> _readEnvelope(
    HttpRequest req,
    PcSession session,
  ) async {
    final body = await utf8.decoder.bind(req).join();
    try {
      final msg = await session.crypto.open(body);
      final seq = (msg['seq'] as num?)?.toInt() ?? -1;
      final ts = (msg['ts'] as num?)?.toInt() ?? 0;
      if (seq <= session.lastClientSeq) return null;
      if ((DateTime.now().millisecondsSinceEpoch - ts).abs() > _tsWindowMs) {
        return null;
      }
      session.lastClientSeq = seq;
      return msg;
    } catch (_) {
      return null;
    }
  }

  Future<void> _respondSealed(
    HttpRequest req,
    PcSession session,
    Map<String, dynamic> obj,
  ) async {
    final out = Map<String, dynamic>.from(obj);
    out['seq'] = ++session.serverSeq;
    out['ts'] = DateTime.now().millisecondsSinceEpoch;
    final body = await session.crypto.seal(out);
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.text
      ..write(body);
    await req.response.close();
  }

  Future<void> _onPoll(HttpRequest req) async {
    final session = _session(req);
    if (session == null) {
      req.response.statusCode =
          404; // sessão desconhecida -> extensão re-vincula
      await req.response.close();
      return;
    }
    final msg = await _readEnvelope(req, session);
    if (msg == null) {
      req.response.statusCode = 401;
      await req.response.close();
      return;
    }
    registry.touch(session.deviceId);
    final obj =
        session.queue.isNotEmpty ? session.queue.removeAt(0) : {'type': 'pong'};
    await _respondSealed(req, session, obj);
  }

  Future<void> _onAck(HttpRequest req) async {
    final session = _session(req);
    if (session == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final msg = await _readEnvelope(req, session);
    if (msg == null) {
      req.response.statusCode = 401;
      await req.response.close();
      return;
    }
    registry.touch(session.deviceId);
    req.response.statusCode = 200;
    await req.response.close();
  }
}
