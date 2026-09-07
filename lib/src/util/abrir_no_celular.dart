// Abre a URL do aluno no navegador do PRÓPRIO celular do professor — o análogo
// local do "Abrir no Computador do Professor" (que abre no Chromebook do
// professor). Aqui não há comando: só um launch externo.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> abrirNoCelular(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(ok ? 'Abrindo no seu celular…' : 'Não consegui abrir esta URL.'),
      ),
    );
}
