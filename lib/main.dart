// Controle de Aula — app de controle (celular).
// Ponto de entrada: Firebase, preferências (tema/nome) e o shell de abas.
// O root é o DONO do PairingController (as abas só o observam).

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/pairing/pairing_controller.dart';
import 'src/pairing/prefs_store.dart';
import 'src/service/foreground_service.dart';
import 'src/service/notification_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/settings_controller.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  prepararServicoAula();
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

  @override
  void initState() {
    super.initState();
    _pairing.notificacoes = _notificacoes;
    _pairing.notificarSites = _settings.notificarSites;
    _pairing.marcarPcProfessor(widget.prefs.teacherPcId);
    // Preferências → controller (toggle de notificações muda em Ajustes).
    _settings.addListener(_sincronizarPrefs);
    // Controller → preferências (marcar PC do professor acontece na UI da
    // Aula, que só conhece o pairing; o root persiste).
    _pairing.addListener(_persistirPcProfessor);
    if (widget.autoStart) {
      _notificacoes.init();
      _pairing.start();
    }
  }

  void _sincronizarPrefs() {
    _pairing.notificarSites = _settings.notificarSites;
  }

  void _persistirPcProfessor() {
    if (_pairing.pcProfessorId != _settings.teacherPcId) {
      _settings.setTeacherPcId(_pairing.pcProfessorId);
    }
  }

  @override
  void dispose() {
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
        title: 'Controle de Aula',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _settings.themeMode,
        home: AppShell(pairing: _pairing, settings: _settings),
      ),
    );
  }
}
