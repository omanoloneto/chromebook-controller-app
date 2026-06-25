// Persiste o par de chaves de longo prazo do professor (sobrevive a reinícios).
// Importante para o TOFU: se a chave mudasse a cada execução, os PCs vinculados
// passariam a rejeitar o app.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'keypair.dart';

class KeyStore {
  static const _fileName = 'teacher_key.txt';

  static Future<DeviceKeyPair> loadOrCreate() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_fileName');
    if (await file.exists()) {
      final parts = (await file.readAsString()).trim().split(':');
      if (parts.length == 2) {
        return DeviceKeyPair.fromBytes(
          pubFromB64url(parts[0]),
          pubFromB64url(parts[1]),
        );
      }
    }
    final kp = await DeviceKeyPair.generate();
    final priv = await kp.privateBytes();
    await file.writeAsString(
      '${pubToB64url(priv)}:${pubToB64url(kp.publicBytes)}',
    );
    return kp;
  }
}
