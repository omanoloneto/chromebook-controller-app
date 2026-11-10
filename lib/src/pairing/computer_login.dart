// Entrada do professor no computador (protocolo §2.1): o app mostra um QR com
// um canal e uma chave efêmera, o celular grava nele a conta Google e a chave
// do professor, e este lado entra na mesma conta e adota a chave.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../cloud/login_handoff.dart';
import '../secure/key_store.dart';

const String kLoginFailedText =
    'Não foi possível entrar pelo celular. Tente de novo.';
const String kInvalidKeyText = 'A chave recebida do celular é inválida.';

enum ComputerLoginStage { opening, waiting, entering, failed, done }

class ComputerLogin extends ChangeNotifier {
  ComputerLogin({
    required this.auth,
    required this.db,
    Future<void> Function(String keys)? saveKeys,
  }) : _saveKeys = saveKeys ?? KeyStore.salvarBruto;

  final AuthGateway auth;
  final RealtimeDb db;
  final Future<void> Function(String keys) _saveKeys;

  ComputerLoginStage stage = ComputerLoginStage.opening;
  String? error;
  String? qrPayload;
  String? teacherName;
  String? schoolUid;

  LoginRequest? _request;
  StreamSubscription<DbEvent>? _subscription;
  bool _disposed = false;

  /// Abre um canal novo; [error] fica na tela junto do QR novo.
  Future<void> start({String? error}) async {
    await _subscription?.cancel();
    _subscription = null;
    _request = null;
    qrPayload = null;
    this.error = error;
    _set(ComputerLoginStage.opening);
    try {
      if (auth.currentUser == null) await auth.signInAnonymously();
      final request = await LoginRequest.create();
      if (_disposed) return;
      _request = request;
      qrPayload = request.qrPayload;
      _subscription = db.ref(request.path).onValue.listen(
            (event) => _onNode(request, event.snapshot.value),
            onError: (Object _) => _fail(),
          );
      _set(ComputerLoginStage.waiting);
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (stage == ComputerLoginStage.done) return;
    error = kLoginFailedText;
    _set(ComputerLoginStage.failed);
  }

  Future<void> _onNode(LoginRequest request, Object? node) async {
    bool current() =>
        !_disposed &&
        stage == ComputerLoginStage.waiting &&
        identical(request, _request);
    if (!current()) return;
    final grant = await request.open(node);
    if (grant == null || !current()) return;
    _set(ComputerLoginStage.entering);
    // A troca de conta reinicia as escutas: esta sai antes.
    await _subscription?.cancel();
    _subscription = null;
    if (!await KeyStore.validPair(grant.keys)) {
      await _discard(request);
      return start(error: kInvalidKeyText);
    }
    try {
      // Chave antes da conta: conta Google sem a chave do professor abriria
      // o app na próxima vez sem conseguir ler nada da escola.
      await _saveKeys(grant.keys);
      await auth.linkGoogle(grant.idToken);
    } catch (_) {
      await _discard(request);
      return start(error: kLoginFailedText);
    }
    await _discard(request);
    teacherName = grant.teacherName;
    schoolUid = grant.schoolUid;
    _set(ComputerLoginStage.done);
  }

  Future<void> _discard(LoginRequest request) async {
    try {
      await db.ref(request.path).remove();
    } catch (_) {}
  }

  void _set(ComputerLoginStage value) {
    if (_disposed) return;
    stage = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
