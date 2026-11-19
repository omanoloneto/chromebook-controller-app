// Portão de entrada do app: sem conta Google não se usa nada, e conta sem
// vínculo com a escola fica esperando a liberação (professor em
// /school/members, monitora em /school/monitores; o fundador é professor).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../cloud/monitoras.dart';
import '../cloud/school_keys.dart';
import '../cloud/school_members.dart';

enum PapelNaEscola { professor, monitora }

enum EstadoDoAcesso { verificando, entrar, semVinculo, liberado }

/// Quanto a tela de "sem vínculo" espera entre uma conferência e outra.
const Duration kConferirVinculo = Duration(seconds: 5);

/// Papel da conta na escola; null = sem vínculo. Lança em erro de rede.
Future<PapelNaEscola?> papelNaEscola(AuthUser user, {RealtimeDb? database}) async {
  // Token fresco: a liberação vale para as rules só com o e-mail no claim.
  await user.refreshIdToken();
  final fundador = await SchoolKeys(database: database).schoolUidPublicado();
  if (fundador != null && fundador == user.uid) return PapelNaEscola.professor;
  final email = user.email ?? user.googleEmail;
  if (email == null) return null;
  if (await SchoolMembers(database: database).liberado(email)) return PapelNaEscola.professor;
  if (await SchoolMonitoras(database: database).liberada(email)) return PapelNaEscola.monitora;
  return null;
}

class AcessoController extends ChangeNotifier {
  AcessoController({
    required AuthUser? Function() usuario,
    Future<PapelNaEscola?> Function(AuthUser user)? papelDe,
    this.papelGuardado,
    this.intervalo = kConferirVinculo,
  })  : _usuario = usuario,
        _papelDe = papelDe ?? papelNaEscola;

  final AuthUser? Function() _usuario;
  final Future<PapelNaEscola?> Function(AuthUser user) _papelDe;
  final Duration intervalo;

  /// Último papel confirmado (prefs): sem internet ao abrir, o app segue com ele.
  PapelNaEscola? papelGuardado;

  EstadoDoAcesso estado = EstadoDoAcesso.verificando;
  PapelNaEscola? papel;
  String? email;

  /// Sem internet e sem papel guardado: a tela diz e tenta de novo sozinha.
  bool semInternet = false;
  Timer? _timer;
  bool _conferindo = false;
  bool _fechado = false;

  Future<void> verificar() async {
    if (_conferindo || _fechado) return;
    _conferindo = true;
    _timer?.cancel();
    try {
      final user = _usuario();
      if (user == null || !user.hasGoogle) {
        _mudar(EstadoDoAcesso.entrar, null);
        return;
      }
      email = user.email ?? user.googleEmail;
      final PapelNaEscola? novo;
      try {
        novo = await _papelDe(user);
      } catch (e) {
        debugPrint('[CdA] conferir vínculo: $e');
        final guardado = papelGuardado;
        if (guardado != null) {
          _mudar(EstadoDoAcesso.liberado, guardado);
        } else {
          semInternet = true;
          _mudar(EstadoDoAcesso.verificando, null);
          _agendar();
        }
        return;
      }
      semInternet = false;
      papelGuardado = novo;
      if (novo == null) {
        _mudar(EstadoDoAcesso.semVinculo, null);
        _agendar();
      } else {
        _mudar(EstadoDoAcesso.liberado, novo);
      }
    } finally {
      _conferindo = false;
    }
  }

  void _agendar() {
    if (_fechado) return;
    _timer?.cancel();
    _timer = Timer(intervalo, () => unawaited(verificar()));
  }

  void _mudar(EstadoDoAcesso e, PapelNaEscola? p) {
    if (_fechado) return;
    estado = e;
    papel = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _fechado = true;
    _timer?.cancel();
    super.dispose();
  }
}
