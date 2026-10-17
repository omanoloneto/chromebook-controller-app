// Push dos recados dos alunos (chat, pedido de liberação, mão levantada) com o
// app fechado. A Cloud Function avisarRecado (firebase/functions) repassa o
// envelope do up/ como chegou — cifrado ponta a ponta — e o celular o decifra
// aqui. A notificação é a mesma do caminho ao vivo (mesmo id): se os dois
// chegarem, o segundo só atualiza o card, sem tocar de novo.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../cloud/up_router.dart';
import '../commands/command.dart';
import '../pairing/class_session_store.dart';
import '../pairing/name_store.dart';
import '../secure/crypto.dart';
import '../secure/key_store.dart';
import '../secure/keypair.dart';
import 'notification_service.dart';

/// Chave do token em /fcm/{uid}: o token tem caracteres que o RTDB não aceita
/// em chave.
String chaveDoToken(String token) =>
    base64Url.encode(sha256.convert(utf8.encode(token)).bytes).substring(0, 22);

/// O que a notificação mostra; [k] = 'chat' | 'pedido' | 'mao'.
typedef RecadoDoPush = ({String k, String deviceId, int ts, String titulo, String corpo});

/// Recado mais velho que isto não toca: o PC poda o up/ em 2 h.
const Duration kRecadoVelho = Duration(hours: 2);

/// Decifra o push da Cloud Function. null = fora do formato, chave de outro
/// professor ou recado velho. [nome] resolve o PC como a tela do app
/// (aluno da aula, apelido, "Unidade N").
Future<RecadoDoPush?> abrirRecado(
  Map<String, dynamic> dados, {
  required DeviceKeyPair professor,
  required String Function(String deviceId, String label) nome,
  required int agoraMs,
}) async {
  final deviceId = dados['d'], pushId = dados['k'], env = dados['e'], pub = dados['p'];
  if (dados['t'] != 'up' || deviceId is! String || deviceId.isEmpty || pushId is! String) return null;
  if (env is! String || pub is! String) return null;
  final ms = pushIdMs(pushId);
  if (ms == null || ms < agoraMs - kRecadoVelho.inMilliseconds) return null;
  final UpMessage? up;
  try {
    final chave = await professor.deriveSessionKey(pubFromB64url(pub));
    up = UpMessage.fromMap(await SessionCrypto(chave).open(env));
  } catch (_) {
    return null;
  }
  if (up == null) return null;
  final label = dados['l'];
  final quem = nome(deviceId, label is String ? label : '');
  return switch (up.type) {
    UpType.chat => (k: 'chat', deviceId: deviceId, ts: ms, titulo: quem, corpo: up.texto!),
    UpType.unblockRequest =>
      (k: 'pedido', deviceId: deviceId, ts: ms, titulo: 'Pedido de liberação', corpo: '$quem: ${up.site}'),
    UpType.raiseHand => (k: 'mao', deviceId: deviceId, ts: ms, titulo: 'Mão levantada', corpo: quem),
    _ => null,
  };
}

/// Nome do PC pelos arquivos do app, como no caminho ao vivo.
Future<String Function(String, String)> nomesLocais() async {
  final aula = await ClassSessionStore.load();
  final nomes = await NameStore.load();
  return (String deviceId, String label) =>
      aula.alunoDe(deviceId) ?? nomes.nameOf(deviceId) ?? (label.isNotEmpty ? label : 'Computador');
}

/// Push com o app em segundo plano ou fechado (isolate próprio). Com o app na
/// frente o FCM não chama isto, e o caminho ao vivo já notificou.
@pragma('vm:entry-point')
Future<void> aoPushEmSegundoPlano(RemoteMessage mensagem) async {
  final bruto = await KeyStore.lerBruto();
  if (bruto == null) return;
  final partes = bruto.split(':');
  final professor = await DeviceKeyPair.fromBytes(pubFromB64url(partes[0]), pubFromB64url(partes[1]));
  final recado = await abrirRecado(
    mensagem.data,
    professor: professor,
    nome: await nomesLocais(),
    agoraMs: DateTime.now().millisecondsSinceEpoch,
  );
  if (recado == null) return;
  final notificacoes = NotificationService();
  await notificacoes.init(pedirPermissao: false);
  await notificacoes.notificarRecado(
    k: recado.k,
    deviceId: recado.deviceId,
    ts: recado.ts,
    titulo: recado.titulo,
    corpo: recado.corpo,
  );
}

/// Token deste celular em /fcm/{uid}/{chave} = {t, ts}; a Cloud Function lê e
/// apaga o que o FCM recusar.
class PushService {
  PushService({FirebaseMessaging? messaging, FirebaseDatabase? database})
      : _messaging = messaging,
        _database = database;

  final FirebaseMessaging? _messaging;
  final FirebaseDatabase? _database;
  StreamSubscription<String>? _renovacao;
  String? _uid;
  String? _chave;

  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;
  FirebaseDatabase get _db => _database ?? FirebaseDatabase.instance;

  /// Chamar depois do login. Falha (sem Google Play, sem rede) só fica no log:
  /// o caminho ao vivo continua notificando.
  Future<void> registrar(String uid) async {
    try {
      if (_uid != uid) await esquecer();
      _uid = uid;
      final token = await _fcm.getToken();
      if (token != null) await _gravar(token);
      _renovacao ??= _fcm.onTokenRefresh.listen((t) => unawaited(_gravar(t).catchError((_) {})));
    } catch (e) {
      debugPrint('[CdA] push: $e');
    }
  }

  Future<void> _gravar(String token) async {
    final uid = _uid;
    if (uid == null) return;
    final chave = chaveDoToken(token);
    await _db.ref('fcm/$uid/$chave').set({'t': token, 'ts': ServerValue.timestamp});
    final antiga = _chave;
    _chave = chave;
    if (antiga != null && antiga != chave) await _db.ref('fcm/$uid/$antiga').remove();
  }

  /// Este celular para de receber os recados da conta.
  Future<void> esquecer() async {
    await _renovacao?.cancel();
    _renovacao = null;
    final uid = _uid, chave = _chave;
    _uid = null;
    _chave = null;
    if (uid != null && chave != null) {
      await _db.ref('fcm/$uid/$chave').remove().catchError((_) {});
    }
  }
}
