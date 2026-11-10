// Sessão da conta num arquivo do perfil do app (Linux).

import 'dart:convert';
import 'dart:io';

import 'rest_auth.dart';

final class FileSessionStore implements SessionStore {
  FileSessionStore(this._file);

  final File _file;

  @override
  Map<String, Object?>? load() {
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void save(Map<String, Object?>? session) {
    if (session == null) {
      if (_file.existsSync()) _file.deleteSync();
      return;
    }
    // Troca atômica: queda no meio da gravação não deixa a sessão pela metade.
    final temp = File('${_file.path}.tmp');
    temp.writeAsStringSync(jsonEncode(session), flush: true);
    temp.renameSync(_file.path);
  }
}
