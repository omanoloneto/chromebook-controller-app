// Controle de Aula — app de controle (celular).
// Ponto de entrada: inicializa o Firebase (transporte v4) e o serviço de aula.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/service/foreground_service.dart';
import 'src/ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  prepararServicoAula();
  runApp(const ControleDeAulaApp());
}

class ControleDeAulaApp extends StatelessWidget {
  const ControleDeAulaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Aula',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2962FF),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
