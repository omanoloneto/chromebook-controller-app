// Controle de Aula — app de controle (celular).
// Ponto de entrada. Esboço: a navegação e as telas ainda serão construídas.

import 'package:flutter/material.dart';

import 'src/ui/home_page.dart';

void main() {
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
