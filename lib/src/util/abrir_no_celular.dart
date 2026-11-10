// Abre a URL do aluno no navegador do PRÓPRIO aparelho do professor (celular
// ou computador) — o análogo local do "Abrir no Computador do Professor" (que
// abre no telão). Aqui não há comando: só um launch externo.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform/host.dart';

String get openHereText =>
    onComputer ? 'Abrir neste computador' : 'Abrir no meu celular';

IconData get openHereIcon => onComputer ? Icons.computer_outlined : Icons.smartphone;

/// A URL vem do histórico do aluno: só página da web chega ao sistema, nunca
/// um esquema que abra arquivo ou outro programa do aparelho do professor.
Uri? webUriOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.isScheme('https') || uri.isScheme('http') ? uri : null;
}

Future<void> abrirNoCelular(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = webUriOf(url);
  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  final abrindo = onComputer ? 'Abrindo neste computador…' : 'Abrindo no seu celular…';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(ok ? abrindo : 'Não consegui abrir esta URL.')),
    );
}
