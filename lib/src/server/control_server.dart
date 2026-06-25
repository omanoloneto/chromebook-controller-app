// Servidor HTTP local do celular — ver docs/protocolo.md.
// O celular ABRE a porta na LAN; a extensão (Chromebook) é CLIENTE e faz
// long-poll. Todo corpo é um envelope AES-256-GCM (crypto.dart).
//
// Rotas:
//   GET  /        -> "controle-de-aula" (teste de conectividade crua)
//   POST /poll    -> segura até ter comando ou ~25s; responde envelope (comando ou pong)
//   POST /ack     -> recebe o ACK cifrado de um comando

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../secure/crypto.dart';
import 'lan.dart';

class ControlServer {
  ControlServer({this.deviceName = 'Celular do professor'});

  final String deviceName;

  HttpServer? _server;
  SessionCrypto? _crypto;
  List<int>? _key;

  String? ip;
  int port = 0;

  final List<Map<String, dynamic>> _queue = [];
  Timer? _livenessTimer;

  int _serverSeq = 0; // servidor -> cliente
  int _lastClientSeq = 0; // cliente -> servidor (anti-replay)
  DateTime? _lastPollAt;
  bool _connected = false;

  static const int _tsWindowMs = 120000;
  static const Duration _connTimeout = Duration(seconds: 8);

  /// Chamado quando o Chromebook conecta/desconecta (baseado nos polls).
  void Function(bool connected)? onConnection;

  /// Chamado a cada ACK recebido (mapa já decifrado).
  void Function(Map<String, dynamic> ack)? onAck;

  List<int> get key => _key!;
  bool get isConnected => _connected;

  Future<void> start() async {
    _key = SessionCrypto.generateKey();
    _crypto = SessionCrypto(_key!);
    ip = await descobrirIpLan();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    port = _server!.port;
    _server!.listen(_handle, onError: (_) {});
    _livenessTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkLiveness());
  }

  Future<void> stop() async {
    _livenessTimer?.cancel();
    await _server?.close(force: true);
    _server = null;
    _setConnected(false);
  }

  /// Enfileira um comando para entregar ao Chromebook no próximo poll.
  void enqueueCommand(Map<String, dynamic> cmd) {
    _queue.add(cmd);
  }

  // ---- internos -------------------------------------------------------------

  Map<String, dynamic> _pong() => {'type': 'pong'};

  void _setConnected(bool v) {
    if (_connected != v) {
      _connected = v;
      onConnection?.call(v);
    }
  }

  void _markPoll() {
    _lastPollAt = DateTime.now();
    _setConnected(true);
  }

  void _checkLiveness() {
    if (_connected &&
        _lastPollAt != null &&
        DateTime.now().difference(_lastPollAt!) > _connTimeout) {
      _setConnected(false);
    }
  }

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
      if (req.method == 'GET' && req.uri.path == '/') {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.text
          ..write('controle-de-aula');
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/poll') {
        await _onPoll(req);
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/ack') {
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

  // Decifra o corpo e aplica anti-replay. Retorna null se inválido.
  Future<Map<String, dynamic>?> _readEnvelope(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    try {
      final msg = await _crypto!.open(body);
      final seq = (msg['seq'] as num?)?.toInt() ?? -1;
      final ts = (msg['ts'] as num?)?.toInt() ?? 0;
      if (seq <= _lastClientSeq) return null;
      if ((DateTime.now().millisecondsSinceEpoch - ts).abs() > _tsWindowMs) {
        return null;
      }
      _lastClientSeq = seq;
      return msg;
    } catch (_) {
      return null;
    }
  }

  Future<void> _respondSealed(HttpRequest req, Map<String, dynamic> obj) async {
    final out = Map<String, dynamic>.from(obj);
    out['seq'] = ++_serverSeq;
    out['ts'] = DateTime.now().millisecondsSinceEpoch;
    final body = await _crypto!.seal(out);
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.text
      ..write(body);
    await req.response.close();
  }

  Future<void> _onPoll(HttpRequest req) async {
    final msg = await _readEnvelope(req);
    if (msg == null) {
      req.response.statusCode = 401;
      await req.response.close();
      return;
    }
    _markPoll();
    // Short-poll: responde na hora (comando da fila ou pong).
    final obj = _queue.isNotEmpty ? _queue.removeAt(0) : _pong();
    await _respondSealed(req, obj);
  }

  Future<void> _onAck(HttpRequest req) async {
    final msg = await _readEnvelope(req);
    if (msg == null) {
      req.response.statusCode = 401;
      await req.response.close();
      return;
    }
    onAck?.call(msg);
    req.response.statusCode = 200;
    await req.response.close();
  }
}
