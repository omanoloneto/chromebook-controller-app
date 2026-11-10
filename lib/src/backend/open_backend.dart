// Abre o servidor do app nesta plataforma. Cada isolate (app e serviço da
// aula) abre o seu.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';

import '../../firebase_options.dart';
import '../platform/session_profile.dart';
import 'backend.dart';
import 'plugin/plugin_backend.dart';
import 'rest/file_session_store.dart';
import 'rest/rest_backend.dart';
import 'rest/rest_config.dart';

Future<Backend> openBackend() async {
  if (Platform.isLinux) {
    final profile = await getApplicationSupportDirectory();
    await SessionProfile.enforce(profile);
    return Backend.instance = restBackend(
      RestConfig.production,
      store: FileSessionStore(File('${profile.path}/auth.json')),
    );
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  return Backend.instance = pluginBackend();
}
