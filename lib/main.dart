// Controle de Aula — app de controle (celular).
// Ponto de entrada: Firebase, preferências (tema/nome) e o shell de abas.
// O root é o DONO do PairingController (as abas só o observam).

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/pairing/pairing_controller.dart';
import 'src/pairing/prefs_store.dart';
import 'src/service/foreground_service.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _pairing.start();
  }

  @override
  void dispose() {
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
