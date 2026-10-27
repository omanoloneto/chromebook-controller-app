// Persiste o par de chaves de longo prazo do professor (sobrevive a reinícios).
// Importante para o TOFU: se a chave mudasse a cada execução, os PCs vinculados
// passariam a rejeitar o app.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'keypair.dart';

class KeyStore {
  static const _fileName = 'teacher_key.txt';

  /// Par do celular guardião do Wi-Fi da escola: fora do backup do Android
  /// (res/xml) e de /backup, e nunca vira a chave da escola nem vai no login
  /// por QR (lerBruto e salvarBruto só mexem no teacher_key.txt).
  static const arquivoGuardiao = 'wifi_guardiao.txt';

  static Future<DeviceKeyPair> loadOrCreate() async {
    final file = await _file();
    if (await file.exists()) {
      final parts = (await file.readAsString()).trim().split(':');
      if (parts.length == 2) {
        return DeviceKeyPair.fromBytes(
          pubFromB64url(parts[0]),
          pubFromB64url(parts[1]),
        );
      }
    }
    return _novo(file);
  }

  /// Ao contrário do teacher_key.txt, o par do guardião é descartável: se o
  /// arquivo estiver ilegível ou torto, vira outro, o nó se cadastra de novo e
  /// um PC sela outra vez. `dir` é injetável para testes.
  static Future<DeviceKeyPair> loadOrCreateGuardiao({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    final file = File('${base.path}/$arquivoGuardiao');
    try {
      final parts = (await file.readAsString()).trim().split(':');
      final kp = await DeviceKeyPair.fromPrivate(pubFromB64url(parts.first));
      if (parts.length == 2 && pubToB64url(kp.publicBytes) == parts.last) {
        return kp;
      }
    } catch (_) {}
    return _novo(file);
  }

  static Future<DeviceKeyPair> _novo(File file) async {
    final kp = await DeviceKeyPair.generate();
    final priv = await kp.privateBytes();
    await file.writeAsString(
      '${pubToB64url(priv)}:${pubToB64url(kp.publicBytes)}',
    );
    return kp;
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Conteúdo bruto ("priv:pub" b64url) — usado p/ publicar a chave da escola.
  static Future<String?> lerBruto() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final s = (await file.readAsString()).trim();
    return s.split(':').length == 2 ? s : null;
  }

  /// Sobrescreve a keypair local (professor ADOTANDO a chave da escola).
  /// ⚠ Perde o acesso ao que era cifrado com a chave antiga.
  static Future<void> salvarBruto(String conteudo) async {
    await (await _file()).writeAsString(conteudo.trim());
  }
}
