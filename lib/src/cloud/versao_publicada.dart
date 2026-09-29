// Última versão do Celita OS no canal de atualização (o mesmo repositório que
// os PCs usam). Só leitura, sem login: é um índice público do APT.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../util/versao.dart';

const kUrlPacotesCelita =
    'https://omanoloneto.github.io/celita-apt/dists/estavel/main/binary-amd64/Packages';

/// Maior versão do celita-os-completo num índice Packages do APT.
String? versaoMaisNovaNoIndice(String packages) {
  String? maior;
  for (final bloco in packages.split(RegExp(r'\n\s*\n'))) {
    final pacote = RegExp(r'^Package: (.+)$', multiLine: true).firstMatch(bloco)?.group(1)?.trim();
    final versao = RegExp(r'^Version: (.+)$', multiLine: true).firstMatch(bloco)?.group(1)?.trim();
    if (pacote != 'celita-os-completo' || versao == null) continue;
    if (maior == null || compararVersoes(versao, maior) > 0) maior = versao;
  }
  return maior;
}

/// null = sem internet ou índice ilegível (o app só deixa de marcar
/// desatualizados; nada quebra).
Future<String?> buscarVersaoPublicada() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(kUrlPacotesCelita));
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final corpo = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    return versaoMaisNovaNoIndice(corpo);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
