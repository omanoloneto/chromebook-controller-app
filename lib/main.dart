// Controle de Aula — app de controle (celular e computador do professor).
// Ponto de entrada: Firebase, preferências (tema/nome) e o shell de abas.
// No computador a conta entra pelo celular antes de qualquer outra tela.
// O root é o DONO do PairingController (as abas só o observam).

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'src/backend/backend.dart';
import 'src/backend/open_backend.dart';
import 'src/cloud/equipe.dart';
import 'src/pairing/acesso_controller.dart';
import 'src/pairing/computer_login.dart';
import 'src/pairing/monitora_controller.dart';
import 'src/pairing/pairing_controller.dart';
import 'src/pairing/prefs_store.dart';
import 'src/platform/host.dart';
import 'src/service/foreground_service.dart';
import 'src/service/notification_service.dart';
import 'src/service/push_service.dart';
import 'src/ui/acesso_page.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/chat_page.dart';
import 'src/ui/computer_login_page.dart';
import 'src/ui/device_page.dart';
import 'src/ui/grade_telas.dart';
import 'src/ui/monitora_shell.dart';
import 'src/ui/recados_page.dart';
import 'src/ui/settings_controller.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await openBackend();
  if (!onComputer) {
    FirebaseMessaging.onBackgroundMessage(aoPushEmSegundoPlano);
    prepararServicoAula();
  }
  // Prefs ANTES do runApp: sem flash de tema errado na abertura.
  final prefs = await PrefsStore.load();
  runApp(ControleDeAulaApp(prefs: prefs));
}

class ControleDeAulaApp extends StatefulWidget {
  const ControleDeAulaApp({super.key, required this.prefs, this.autoStart = true});

  final PrefsStore prefs;

  /// Em testes, passe false para não iniciar o transporte.
  final bool autoStart;

  @override
  State<ControleDeAulaApp> createState() => _ControleDeAulaAppState();
}

class _ControleDeAulaAppState extends State<ControleDeAulaApp> {
  late final SettingsController _settings = SettingsController(widget.prefs);
  late final PairingController _pairing =
      PairingController(deviceName: widget.prefs.teacherName);
  final NotificationService _notificacoes = NotificationService();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<ToqueNotificacao>? _toques;
  ComputerLogin? _login;
  MonitoraController? _monitora;
  bool _pairingIniciado = false;
  late final AcessoController _acesso = AcessoController(
    usuario: _usuarioAtual,
    papelGuardado: _settings.modoMonitora
        ? PapelNaEscola.monitora
        : (_settings.schoolUid != null ? PapelNaEscola.professor : null),
  );

  /// Professor sem escola no celular: adotar a chave da escola falhou.
  String? _erroAoEntrar;

  AuthUser? _usuarioAtual() {
    try {
      return Backend.instance.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _pairing.notificacoes = _notificacoes;
    if (widget.autoStart && !onComputer) _pairing.push = PushService();
    _pairing.notificarSites = _settings.notificarSites;
    _pairing.schoolUid = widget.prefs.schoolUid;
    _pairing.prefs = widget.prefs;
    _pairing.marcarPcProfessor(widget.prefs.teacherPcId);
    // Preferências → controller (toggle de notificações muda em Ajustes).
    _settings.addListener(_sincronizarPrefs);
    // Controller → preferências (marcar PC do professor acontece na UI da
    // Aula, que só conhece o pairing; o root persiste).
    _pairing.addListener(_persistirPcProfessor);
    _acesso.addListener(_aoMudarAcesso);
    if (widget.autoStart) {
      _toques = _notificacoes.toques.listen(_abrirPc);
      _notificacoes.init().then((_) {
        final abertura = _notificacoes.consumirAbertura();
        if (abertura != null) _abrirPc(abertura);
      });
      unawaited(_acesso.verificar());
    }
  }

  // O portão decidiu: entrar, esperar a liberação ou abrir o app do papel.
  Future<void> _aoMudarAcesso() async {
    if (!mounted) return;
    switch ((_acesso.estado, _acesso.papel)) {
      case (EstadoDoAcesso.entrar, _) when onComputer && _login == null:
        _openComputerLogin();
      case (EstadoDoAcesso.liberado, PapelNaEscola.monitora):
        await _settings.setModoMonitora(true);
        if (_monitora == null) _abrirMonitora();
      case (EstadoDoAcesso.liberado, PapelNaEscola.professor):
        final antiga = _monitora;
        _monitora = null;
        antiga?.dispose();
        await _settings.setModoMonitora(false);
        if (!_pairingIniciado) {
          if (_pairing.schoolUid == null) {
            _erroAoEntrar = await _pairing.entrarNoWorkspace();
            if (_erroAoEntrar != null) break;
          }
          _iniciarPairing();
        }
      default:
        break;
    }
    if (mounted) setState(() {});
  }

  Future<void> _entrarComGoogle() async {
    final auth = Backend.instance.auth;
    if (auth.currentUser == null) await auth.signInAnonymously();
    final r = await _pairing.entrarComGoogle();
    if (r.startsWith('erro:')) debugPrint('[CdA] login Google: ${r.substring(5)}');
    await _acesso.verificar();
  }

  // "Usar outra conta" (sem vínculo) e "Sair" da monitora.
  Future<void> _sairDaConta() async {
    final antiga = _monitora;
    _monitora = null;
    antiga?.dispose();
    await _settings.setModoMonitora(false);
    await _pairing.sairDaConta();
    _acesso.papelGuardado = null;
    await _acesso.verificar();
  }

  void _iniciarPairing() {
    _pairingIniciado = true;
    _pairing.start();
  }

  void _abrirMonitora() {
    final user = Backend.instance.auth.currentUser;
    final email = user?.email ?? user?.googleEmail;
    // Sem nome em Ajustes, o aluno vê "Monitora" (e não "Professor").
    String nome() => _settings.nomeProfessor == 'Professor' ? 'Monitora' : _settings.nomeProfessor;
    _monitora = MonitoraController(
      meuUid: user?.uid,
      nome: nome,
      presenca: user != null && email != null
          ? PresencaNaEquipe(papel: PapelNaEquipe.monitora, uid: user.uid, email: email, nome: nome)
          : null,
    )..start();
  }

  void _openComputerLogin() {
    final backend = Backend.instance;
    _login = ComputerLogin(auth: backend.auth, db: backend.db)
      ..addListener(_onComputerLogin)
      ..start();
  }

  Future<void> _onComputerLogin() async {
    final login = _login;
    if (login == null || login.stage != ComputerLoginStage.done) return;
    login.removeListener(_onComputerLogin);
    final name = login.teacherName;
    if (name != null) {
      await _settings.setNomeProfessor(name);
      _pairing.deviceName = name;
    }
    _pairing.schoolUid = login.schoolUid;
    await _settings.setSchoolUid(login.schoolUid);
    if (!mounted) return;
    setState(() => _login = null);
    login.dispose();
    await _acesso.verificar();
  }

  // Toque numa notificação: alerta de site leva à tela do PC; recado de
  // chat ou mão, à conversa; pedido de liberação, a Recados. Se a tela já
  // estiver aberta, volta até ela em vez de empilhar outra igual.
  void _abrirPc(ToqueNotificacao toque) {
    final nav = _navigator.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirPc(toque));
      return;
    }
    final (String nome, Route<void> Function() rota) = switch (toque.k) {
      'chat' || 'mao' => (
          rotaDaConversa(toque.deviceId),
          () => rotaChatPage(_pairing, toque.deviceId),
        ),
      'pedido' => (rotaDosRecados, () => rotaRecadosPage(_pairing)),
      _ => (
          rotaDoPc(toque.deviceId),
          () => rotaDevicePage(_pairing, toque.deviceId),
        ),
    };
    nav.popUntil((r) => r.settings.name == nome || r.isFirst);
    var jaAberta = false;
    nav.popUntil((r) {
      jaAberta = r.settings.name == nome;
      return true;
    });
    if (jaAberta) return;
    nav.push(rota());
  }

  void _sincronizarPrefs() {
    _pairing.notificarSites = _settings.notificarSites;
  }

  void _persistirPcProfessor() {
    if (_pairing.pcProfessorId != _settings.teacherPcId) {
      _settings.setTeacherPcId(_pairing.pcProfessorId);
    }
    // Workspace criado/adotado em Ajustes: o root persiste (padrão acima).
    if (_pairing.schoolUid != _settings.schoolUid) {
      _settings.setSchoolUid(_pairing.schoolUid);
    }
  }

  @override
  void dispose() {
    _toques?.cancel();
    _login?.dispose();
    _monitora?.dispose();
    _acesso.removeListener(_aoMudarAcesso);
    _acesso.dispose();
    _settings.removeListener(_sincronizarPrefs);
    _pairing.removeListener(_persistirPcProfessor);
    _pairing.stop();
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        // A grade de telas para quando outra tela cobre a aba Aula.
        navigatorObservers: [observadorDeRotas],
        title: 'Controle de Aula',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _settings.themeMode,
        home: _inicio(),
      ),
    );
  }

  Widget _inicio() {
    final login = _login;
    if (login != null) return ComputerLoginPage(login: login);
    // Testes de widget montam o app sem portão nem transporte.
    if (!widget.autoStart) return AppShell(pairing: _pairing, settings: _settings);
    final monitora = _monitora;
    if (monitora != null) return MonitoraShell(controller: monitora, onSair: _sairDaConta);
    if (_erroAoEntrar != null) {
      return TelaDeEspera(
        texto: _erroAoEntrar!,
        onTentarDeNovo: () {
          setState(() => _erroAoEntrar = null);
          unawaited(_aoMudarAcesso());
        },
      );
    }
    return switch (_acesso.estado) {
      EstadoDoAcesso.entrar => TelaDeEntrar(onEntrar: _entrarComGoogle),
      EstadoDoAcesso.semVinculo => TelaSemVinculo(email: _acesso.email, onOutraConta: _sairDaConta),
      EstadoDoAcesso.verificando => TelaDeEspera(
          texto: _acesso.semInternet ? 'Sem internet. Tentando de novo…' : null,
        ),
      EstadoDoAcesso.liberado when _pairingIniciado => AppShell(pairing: _pairing, settings: _settings),
      EstadoDoAcesso.liberado => const TelaDeEspera(),
    };
  }
}
