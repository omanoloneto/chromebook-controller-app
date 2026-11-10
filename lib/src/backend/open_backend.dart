// Abre o servidor do app nesta plataforma. Cada isolate (app e serviço da
// aula) abre o seu.

import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import 'backend.dart';
import 'plugin/plugin_backend.dart';

Future<Backend> openBackend() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  return Backend.instance = pluginBackend();
}
