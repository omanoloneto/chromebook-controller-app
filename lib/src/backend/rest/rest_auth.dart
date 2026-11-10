// Conta do professor por REST (Identity Toolkit + Secure Token), para o Linux.

import 'dart:async';
import 'dart:convert';

import '../backend.dart';
import 'rest_config.dart';
import 'rest_http.dart';

const Duration kRefreshMargin = Duration(minutes: 5);

// Só com HTTP 400 estes códigos dizem que a conta morreu no servidor.
const Set<String> _deadCodes = {
  'INVALID_REFRESH_TOKEN',
  'TOKEN_EXPIRED',
  'USER_NOT_FOUND',
  'USER_DISABLED',
  'INVALID_GRANT',
  'MISSING_REFRESH_TOKEN',
};

const Set<String> _takenCodes = {
  'CREDENTIAL_ALREADY_IN_USE',
  'EMAIL_EXISTS',
  'FEDERATED_USER_ID_ALREADY_LINKED',
};

/// Onde a sessão (uid + refresh token) fica entre uma abertura e outra.
abstract interface class SessionStore {
  Map<String, Object?>? load();
  void save(Map<String, Object?>? session);
}

final class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  Map<String, Object?>? _session;

  @override
  Map<String, Object?>? load() => _session;

  @override
  void save(Map<String, Object?>? session) => _session = session;
}

final class _Session {
  const _Session({
    required this.uid,
    required this.refreshToken,
    this.email,
    this.hasGoogle = false,
  });

  final String uid;
  final String refreshToken;
  final String? email;
  final bool hasGoogle;

  static _Session? fromJson(Map<String, Object?>? json) {
    final uid = json?['uid'];
    final refreshToken = json?['refreshToken'];
    if (uid is! String || refreshToken is! String) return null;
    return _Session(
      uid: uid,
      refreshToken: refreshToken,
      email: json?['email'] as String?,
      hasGoogle: json?['hasGoogle'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'uid': uid,
        'refreshToken': refreshToken,
        'email': email,
        'hasGoogle': hasGoogle,
      };
}

final class RestAuth implements AuthGateway {
  RestAuth({
    required RestHttp http,
    required RestConfig config,
    required SessionStore store,
  })  : _http = http,
        _config = config,
        _store = store,
        _session = _Session.fromJson(store.load());

  final RestHttp _http;
  final RestConfig _config;
  final SessionStore _store;
  final StreamController<void> _accountChanges = StreamController.broadcast();

  _Session? _session;
  String? _idToken;
  DateTime? _expiresAt;
  Future<void>? _refreshing;

  /// Avisa quando o uid muda (entrou, trocou de conta ou a conta morreu).
  Stream<void> get accountChanges => _accountChanges.stream;

  DateTime? get tokenExpiresAt => _expiresAt;

  @override
  AuthUser? get currentUser {
    final session = _session;
    return session == null ? null : _RestUser(this, session);
  }

  /// Token válido da conta atual, renovado quando perto de vencer; null sem
  /// conta (as leituras públicas seguem sem ele).
  Future<String?> idTokenOrNull({bool force = false}) async {
    if (_session == null) return null;
    if (force || !_tokenIsFresh) {
      await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    }
    return _idToken;
  }

  bool get _tokenIsFresh {
    final expiresAt = _expiresAt;
    return _idToken != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(kRefreshMargin));
  }

  @override
  Future<AuthUser> signInAnonymously() async {
    final reply = await _post(
      Uri.parse('${_config.identityOrigin}/v1/accounts:signUp')
          .replace(queryParameters: {'key': _config.apiKey}),
      jsonEncode({'returnSecureToken': true}),
      'application/json',
    );
    if (reply.status != 200) {
      throw _error('internal-error', 'signup_http_${reply.status}');
    }
    _adoptIdentityReply(reply.jsonMap, 'signup');
    return currentUser!;
  }

  @override
  Future<GoogleLink> linkGoogle(String idToken) async {
    final before = _session?.uid;
    final current = await idTokenOrNull();
    var reply = await _signInWithIdp(idToken, current);
    if (current != null && _takenCodes.contains(_errorCode(reply))) {
      reply = await _signInWithIdp(idToken, null);
    }
    if (reply.status != 200) {
      throw _error('invalid-credential', 'idp_http_${reply.status}');
    }
    _adoptIdentityReply(reply.jsonMap, 'idp');
    return _session?.uid == before ? GoogleLink.linked : GoogleLink.switched;
  }

  Future<HttpReply> _signInWithIdp(String googleIdToken, String? current) =>
      _post(
        Uri.parse('${_config.identityOrigin}/v1/accounts:signInWithIdp')
            .replace(queryParameters: {'key': _config.apiKey}),
        jsonEncode({
          'postBody': Uri(
            queryParameters: {
              'id_token': googleIdToken,
              'providerId': 'google.com',
            },
          ).query,
          'requestUri': 'http://localhost',
          'returnSecureToken': true,
          if (current != null) 'idToken': current,
        }),
        'application/json',
      );

  Future<void> _refresh() async {
    final session = _session;
    if (session == null) throw _error('no-current-user');
    final reply = await _post(
      Uri.parse('${_config.tokenOrigin}/v1/token')
          .replace(queryParameters: {'key': _config.apiKey}),
      Uri(
        queryParameters: {
          'grant_type': 'refresh_token',
          'refresh_token': session.refreshToken,
        },
      ).query,
      'application/x-www-form-urlencoded',
    );
    // Trocou de conta durante a chamada: a resposta é da conta antiga.
    if (!identical(session, _session)) return;
    if (reply.status != 200) {
      final code = _errorCode(reply);
      if (reply.status == 400 && _deadCodes.contains(code)) {
        _forget();
        throw _error('user-token-expired', code);
      }
      throw _error('internal-error', 'refresh_http_${reply.status}');
    }
    final data = reply.jsonMap;
    _adopt(
      uid: data['user_id'],
      idToken: data['id_token'],
      refreshToken: data['refresh_token'],
      expiresIn: data['expires_in'],
      what: 'refresh',
    );
  }

  void _adoptIdentityReply(Map<String, Object?> data, String what) => _adopt(
        uid: data['localId'],
        idToken: data['idToken'],
        refreshToken: data['refreshToken'],
        expiresIn: data['expiresIn'],
        what: what,
      );

  void _adopt({
    required Object? uid,
    required Object? idToken,
    required Object? refreshToken,
    required Object? expiresIn,
    required String what,
  }) {
    if (uid is! String ||
        idToken is! String ||
        refreshToken is! String ||
        uid.isEmpty ||
        idToken.isEmpty ||
        refreshToken.isEmpty) {
      throw _error('internal-error', '${what}_invalid_reply');
    }
    final claims = _claims(idToken);
    final firebase = claims['firebase'];
    final identities = firebase is Map ? firebase['identities'] : null;
    final before = _session?.uid;
    final session = _Session(
      uid: uid,
      refreshToken: refreshToken,
      email: claims['email'] as String?,
      hasGoogle: identities is Map && identities.containsKey('google.com'),
    );
    _session = session;
    _idToken = idToken;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: int.tryParse('$expiresIn') ?? 3600));
    _store.save(session.toJson());
    if (before != uid) _accountChanges.add(null);
  }

  void _forget() {
    _session = null;
    _idToken = null;
    _expiresAt = null;
    _store.save(null);
    _accountChanges.add(null);
  }

  Future<HttpReply> _post(Uri uri, String body, String contentType) async {
    try {
      return await _http.send(
        'POST',
        uri,
        headers: {'content-type': contentType},
        body: utf8.encode(body),
      );
    } on NetworkFailure catch (e) {
      throw _error('network-request-failed', e.reason);
    }
  }

  /// Código do erro do Identity Toolkit, que às vezes vem com HTTP 200.
  static String _errorCode(HttpReply reply) {
    final data = reply.jsonMap;
    final error = data['error'];
    final message =
        error is Map ? error['message'] : error ?? data['errorMessage'];
    return '${message ?? ''}'.split(':').first.trim();
  }

  static Map<String, Object?> _claims(String jwt) {
    try {
      final payload = jwt.split('.')[1];
      final json = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      final claims = jsonDecode(json);
      return claims is Map<String, Object?> ? claims : const {};
    } on Exception {
      return const {};
    } on RangeError {
      return const {};
    }
  }

  static FirebaseException _error(String code, [String? message]) =>
      FirebaseException(plugin: 'firebase_auth', code: code, message: message);
}

final class _RestUser implements AuthUser {
  _RestUser(this._auth, this._seen);

  final RestAuth _auth;
  final _Session _seen;

  // Depois de renovar o token, a mesma conta pode ter e-mail novo.
  _Session get _now {
    final session = _auth._session;
    return session != null && session.uid == _seen.uid ? session : _seen;
  }

  @override
  String get uid => _seen.uid;

  @override
  String? get email => _now.email;

  @override
  bool get hasGoogle => _now.hasGoogle;

  @override
  String? get googleEmail => _now.hasGoogle ? _now.email : null;

  @override
  Future<void> refreshIdToken() => _auth.idTokenOrNull(force: true);
}
