// Escuta do banco por SSE: um stream por raiz, repartido entre os ouvintes
// de dentro dela. O servidor é a verdade: nada de eco local de escrita.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../backend.dart';
import 'rest_auth.dart';
import 'rest_http.dart';
import 'rest_tree.dart';

enum ListenKind { value, childAdded, childRemoved }

final class StreamTimings {
  const StreamTimings({
    this.watchdog = const Duration(seconds: 90),
    this.minBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 60),
  });

  /// Silêncio que denuncia conexão morta (o servidor manda keep-alive a cada 30 s).
  final Duration watchdog;
  final Duration minBackoff;
  final Duration maxBackoff;
}

typedef StreamUri = Uri Function(List<String> path, String? token);

final class StreamHub {
  StreamHub({
    required RestHttp http,
    required RestAuth auth,
    required StreamUri uriFor,
    StreamTimings timings = const StreamTimings(),
  })  : _http = http,
        _auth = auth,
        _uriFor = uriFor,
        _timings = timings {
    _accountSub = auth.accountChanges.listen((_) {
      for (final root in _roots.values.toList()) {
        root.restart();
      }
    });
  }

  final RestHttp _http;
  final RestAuth _auth;
  final StreamUri _uriFor;
  final StreamTimings _timings;
  final Map<String, _Root> _roots = {};
  late final StreamSubscription<void> _accountSub;

  Stream<DbEvent> listen(List<String> path, ListenKind kind) {
    final rootPath = _rootOf(path);
    final listener = _Listener(
      path.sublist(rootPath.length),
      kind,
      path.isEmpty ? null : path.last,
    );
    final rootKey = rootPath.join('/');
    listener.controller = StreamController<DbEvent>(
      onListen: () => _roots
          .putIfAbsent(rootKey, () => _Root(this, rootPath))
          .add(listener),
      onCancel: () {
        final root = _roots[rootKey];
        if (root == null) return;
        root.listeners.remove(listener);
        if (root.listeners.isEmpty) {
          _roots.remove(rootKey);
          root.close();
        }
      },
    );
    return listener.controller.stream;
  }

  // As regras dão leitura no PC inteiro, e o app escuta uma dúzia de nós de
  // cada um: um stream por PC em vez de um por nó.
  static List<String> _rootOf(List<String> path) =>
      path.length > 2 && path.first == 'devices' ? path.sublist(0, 2) : path;

  void close() {
    _accountSub.cancel();
    for (final root in _roots.values.toList()) {
      root.close();
    }
    _roots.clear();
  }
}

final class _Denied implements Exception {
  const _Denied();
}

final class _Reauth implements Exception {
  const _Reauth();
}

final class _Listener {
  _Listener(this.path, this.kind, this.key);

  final List<String> path;
  final ListenKind kind;
  final String? key;
  late final StreamController<DbEvent> controller;

  bool _emitted = false;
  Object? _last;

  bool touches(List<String> changed) {
    final shared = min(changed.length, path.length);
    for (var i = 0; i < shared; i++) {
      if (changed[i] != path[i]) return false;
    }
    return true;
  }

  void sync(Object? rootTree) {
    if (controller.isClosed) return;
    final now = valueAt(rootTree, path);
    final before = _last;
    if (kind == ListenKind.value) {
      if (_emitted && sameTree(now, before)) return;
      _emitted = true;
      _last = now;
      controller.add(DbEvent(RestSnapshot(key, export(now))));
      return;
    }
    _last = now;
    const empty = <String, Object?>{};
    final old = before is Map<String, Object?> ? before : empty;
    final current = now is Map<String, Object?> ? now : empty;
    final (from, to) =
        kind == ListenKind.childAdded ? (current, old) : (old, current);
    final keys = [
      for (final key in from.keys)
        if (!to.containsKey(key)) key,
    ]..sort(compareKeys);
    for (final key in keys) {
      controller.add(DbEvent(RestSnapshot(key, export(from[key]))));
    }
  }
}

final class _Root {
  _Root(this._hub, this._path);

  final StreamHub _hub;
  final List<String> _path;
  final Set<_Listener> listeners = {};

  Object? _tree;
  bool _synced = false;
  bool _running = false;
  bool _closed = false;
  bool _forceToken = false;
  bool _skipPause = false;
  bool _sessionSynced = false;
  int _epoch = 0;
  StreamSubscription<String>? _lines;
  Completer<void>? _reading;
  Completer<void>? _pause;
  Timer? _pauseTimer;
  Timer? _renewal;

  void add(_Listener listener) {
    listeners.add(listener);
    if (!_running) {
      _running = true;
      unawaited(_run());
    } else if (_synced) {
      scheduleMicrotask(() {
        if (listeners.contains(listener)) listener.sync(_tree);
      });
    }
  }

  /// Reabre o stream já (conta trocada): o put inicial corrige as diferenças.
  void restart() {
    _epoch++;
    _skipPause = true;
    _hangUp();
    _endPause();
  }

  void close() {
    _closed = true;
    _hangUp();
    _endPause();
  }

  Future<void> _run() async {
    final timings = _hub._timings;
    var backoff = timings.minBackoff;
    while (!_closed) {
      _sessionSynced = false;
      _skipPause = false;
      try {
        await _session();
      } on _Denied {
        _deny();
        return;
      } on Exception {
        // Rede ou conta: tenta de novo depois da pausa.
      }
      if (_closed) return;
      if (_sessionSynced) backoff = timings.minBackoff;
      if (_skipPause) continue;
      await _wait(backoff);
      if (backoff >= timings.maxBackoff) _forceToken = true;
      backoff = backoff * 2 < timings.maxBackoff
          ? backoff * 2
          : timings.maxBackoff;
    }
  }

  // Como no SDK: quem escutava recebe o erro e a escuta acaba.
  void _deny() {
    _running = false;
    _tree = null;
    _synced = false;
    final error = FirebaseException(
      plugin: 'firebase_database',
      code: 'permission-denied',
    );
    for (final listener in listeners.toList()) {
      if (!listener.controller.isClosed) listener.controller.addError(error);
    }
  }

  Future<void> _session() async {
    final auth = _hub._auth;
    final epoch = _epoch;
    final forced = _forceToken;
    _forceToken = false;
    var token = await auth.idTokenOrNull(force: forced);
    var response = await _hub._http.openStream(_hub._uriFor(_path, token));
    if (_refused(response) && token != null && !forced) {
      // Antes de dar a escuta por negada, descarta o token velho.
      await response.drain<void>();
      token = await auth.idTokenOrNull(force: true);
      response = await _hub._http.openStream(_hub._uriFor(_path, token));
    }
    if (_closed || epoch != _epoch) {
      await response.listen((_) {}).cancel();
      return;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      if (_refused(response)) throw const _Denied();
      return;
    }

    final reading = _reading = Completer<void>();
    var denied = false;
    final expiresAt = auth.tokenExpiresAt;
    if (token != null && expiresAt != null) {
      final wait =
          expiresAt.subtract(kRefreshMargin).difference(DateTime.now());
      // Token que já nasce vencendo não marca renovação: o servidor avisa
      // com auth_revoked, e religar em seguida viraria um laço.
      if (wait > Duration.zero) {
        _renewal = Timer(wait, () {
          _forceToken = true;
          _skipPause = true;
          _hangUp();
        });
      }
    }
    String? event;
    _lines = response
        .timeout(_hub._timings.watchdog)
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          try {
            _onEvent(event, line.substring(5).trim());
          } on _Denied {
            denied = true;
            _hangUp();
          } on _Reauth {
            _forceToken = true;
            _skipPause = true;
            _hangUp();
          } catch (_) {
            // Evento ilegível: reabre, e o put inicial ressincroniza.
            _hangUp();
          }
        }
      },
      onError: (Object _) => _hangUp(),
      onDone: _hangUp,
      cancelOnError: true,
    );
    await reading.future;
    if (denied) throw const _Denied();
  }

  static bool _refused(HttpClientResponse response) =>
      response.statusCode == HttpStatus.unauthorized ||
      response.statusCode == HttpStatus.forbidden;

  void _onEvent(String? event, String data) {
    switch (event) {
      case 'put' || 'patch':
        final message = jsonDecode(data) as Map<String, Object?>;
        final at = splitPath(message['path'] as String?);
        if (event == 'put') {
          _tree = withValueAt(_tree, at, normalize(message['data']));
        } else {
          final changes = message['data'] as Map<String, Object?>;
          for (final change in changes.entries) {
            _tree = withValueAt(
              _tree,
              [...at, ...splitPath(change.key)],
              normalize(change.value),
            );
          }
        }
        final first = !_synced;
        _synced = true;
        _sessionSynced = true;
        for (final listener in listeners.toList()) {
          if (first || listener.touches(at)) listener.sync(_tree);
        }
      case 'cancel':
        throw const _Denied();
      case 'auth_revoked':
        throw const _Reauth();
    }
  }

  void _hangUp() {
    _renewal?.cancel();
    _renewal = null;
    final lines = _lines;
    _lines = null;
    if (lines != null) unawaited(lines.cancel());
    final reading = _reading;
    if (reading != null && !reading.isCompleted) reading.complete();
  }

  Future<void> _wait(Duration duration) {
    final pause = _pause = Completer<void>();
    _pauseTimer = Timer(duration, _endPause);
    return pause.future;
  }

  void _endPause() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    final pause = _pause;
    if (pause != null && !pause.isCompleted) pause.complete();
  }
}
