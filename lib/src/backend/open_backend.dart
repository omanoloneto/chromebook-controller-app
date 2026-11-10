// Abre o servidor do app nesta plataforma. Cada isolate (app e serviço da
// aula) abre o seu.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import 'backend.dart';
import 'plugin/plugin_backend.dart';
import 'rest/rest_auth.dart';
import 'rest/rest_backend.dart';
import 'rest/rest_config.dart';

Future<Backend> openBackend() async {
  if (Platform.isLinux) {
    return Backend.instance = restBackend(
      RestConfig.production,
      store: MemorySessionStore(),
    );
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  return Backend.instance = pluginBackend();
}
