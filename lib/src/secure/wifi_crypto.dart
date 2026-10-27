// Chave da frota do Wi-Fi da escola (docs/protocolo.md §9) no celular
// guardião: abre a que um PC selou para ele e sela uma entrega para cada PC.
// Casa byte a byte com o agente do Celita (vetor em test/wifi_guardiao_test.dart).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'keypair.dart';

final List<int> _rotuloKcv = utf8.encode('wifi-frota-kcv-v1');

/// base64url, sem "=", de HMAC-SHA256(chave, "wifi-frota-kcv-v1").
Future<String> kcvDaChave(List<int> chave) async {
  final mac =
      await Hmac.sha256().calculateMac(_rotuloKcv, secretKey: SecretKey(chave));
  return pubToB64url(mac.bytes);
}

/// A chave que o PC [pubDoPc] selou para este guardião, ou null se não abre
/// ou se não é a da escola (kcv diferente).
Future<List<int>?> abrirChaveDaFrota({
  required DeviceKeyPair guardiao,
  required String pubDoPc,
  required String env,
  required String kcv,
}) async {
  try {
    final embrulho = await guardiao.deriveWifiWrapKey(pubFromB64url(pubDoPc));
    final conteudo = await SessionCrypto(embrulho).open(env);
    final k = conteudo['v'] == 1 && conteudo['k'] is String
        ? SessionCrypto.keyFromBase64url(conteudo['k'] as String)
        : const <int>[];
    return k.length == 32 && await kcvDaChave(k) == kcv ? k : null;
  } catch (_) {
    return null;
  }
}

/// Entrega {pub, env, kcv} para o PC [pubDoPc], com um par efêmero só dela. O
/// kcv é público e diz ao guardião se a vaga ainda é da chave de agora.
Future<Map<String, String>> selarEntrega(
  List<int> chave,
  String pubDoPc,
) async {
  final efemero = await DeviceKeyPair.generate();
  final embrulho = await efemero.deriveWifiWrapKey(pubFromB64url(pubDoPc));
  return {
    'pub': pubToB64url(efemero.publicBytes),
    'env': await SessionCrypto(embrulho)
        .seal({'v': 1, 'k': SessionCrypto.keyToBase64url(chave)}),
    'kcv': await kcvDaChave(chave),
  };
}
