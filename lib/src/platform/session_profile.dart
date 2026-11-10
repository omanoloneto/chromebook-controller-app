// No computador o login do professor vale só para a sessão gráfica em que foi
// feito: os PCs da escola são compartilhados, e sair da conta, reiniciar ou
// desligar apaga chave, conta e stores.

import 'dart:convert';
import 'dart:io';

const String kBootIdPath = '/proc/sys/kernel/random/boot_id';

final class SessionProfile {
  static const stampFile = 'session.json';

  static Map<String, String> currentStamp({
    String bootIdPath = kBootIdPath,
    Map<String, String>? environment,
  }) {
    var boot = '';
    try {
      boot = File(bootIdPath).readAsStringSync().trim();
    } on FileSystemException {
      // sem /proc: só a sessão identifica
    }
    final session = (environment ?? Platform.environment)['XDG_SESSION_ID'] ?? '';
    return {'boot': boot, 'session': session};
  }

  /// Apaga o perfil deixado por outra sessão e carimba esta. Devolve true se
  /// apagou.
  static Future<bool> enforce(Directory dir, {Map<String, String>? stamp}) async {
    final current = stamp ?? currentStamp();
    await dir.create(recursive: true);
    await _restrict(dir);
    final file = File('${dir.path}/$stampFile');
    if (_sameStamp(await _read(file), current)) return false;
    var wiped = false;
    await for (final entry in dir.list(followLinks: false)) {
      try {
        await entry.delete(recursive: true);
        wiped = true;
      } on FileSystemException {
        // o que não sair agora sai na próxima abertura
      }
    }
    await file.writeAsString(jsonEncode(current), flush: true);
    return wiped;
  }

  static Future<Object?> _read(File file) async {
    try {
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static bool _sameStamp(Object? saved, Map<String, String> current) =>
      saved is Map &&
      saved.length == current.length &&
      current.entries.every((e) => saved[e.key] == e.value);

  static Future<void> _restrict(Directory dir) async {
    try {
      await Process.run('chmod', ['700', dir.path]);
    } on ProcessException {
      // sem chmod (teste fora do Linux): a pasta fica com o padrão do sistema
    }
  }
}
