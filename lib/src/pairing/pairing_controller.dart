// Orquestra o transporte Firebase: carrega o par de chaves do professor,
// autentica (Auth anônima), liga o FirebaseTransport e expõe a lista de PCs +
// comandos + nomes + regras + favoritos. É um
// ChangeNotifier: as telas observam.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'; // também exporta FirebaseException
import 'package:firebase_database/firebase_database.dart' show FirebaseDatabase;
import 'package:crypto/crypto.dart' as c;
import 'package:flutter/foundation.dart';

import 'package:google_sign_in/google_sign_in.dart';

import '../cloud/archive_store.dart';
import '../cloud/backup_store.dart';
import '../cloud/aula_locks.dart';
import '../cloud/broadcast_target.dart';
import '../cloud/conversa.dart';
import '../cloud/entrega.dart';
import '../cloud/firebase_transport.dart';
import '../cloud/history_store.dart';
import '../cloud/login_handoff.dart';
import '../cloud/qr_payload.dart';
import '../cloud/school_keys.dart';
import '../cloud/school_members.dart';
import '../cloud/school_sync.dart';
import '../cloud/session_registry.dart';
import '../cloud/up_router.dart';
import '../cloud/versao_publicada.dart';
import '../commands/class_view.dart';
import '../commands/command.dart';
import '../commands/domain_rules.dart';
import '../commands/filtros.dart';
import '../commands/liberacao.dart';
import '../secure/history_crypto.dart';
import '../secure/key_store.dart';
import '../secure/school_crypto.dart';
import '../service/foreground_service.dart';
import '../service/notification_service.dart';
import '../ui/textos_erro.dart';
import '../util/ids.dart';
import '../util/versao.dart';
import 'class_session_store.dart';
import 'favorites_store.dart';
import 'home_store.dart';
import 'name_store.dart';
import 'prefs_store.dart';
import 'prova_store.dart';
import 'rules_store.dart';
import 'students_store.dart';
import 'unit_store.dart';
import 'wallpaper_store.dart';

class PairingController extends ChangeNotifier {
  PairingController({this.deviceName = 'Professor'});

  /// Nome do professor (popup da extensão). Alterável em Ajustes.
  String deviceName;

  FirebaseTransport? _transport;
  HistoryStore? _history;
  BackupStore? _backup;
  Timer? _backupTimer;

  /// Keypair do professor já está na nuvem (backup ativado)?
  bool backupAtivo = false;
  NameStore? _names;
  UnitStore? _units;
  RulesStore? _rules;
  FavoritesStore? _favorites;
  HomeStore? _home;
  WallpaperStore? _wallpaper;
  String? _erroPaginaInicial;
  StudentsStore? _students;
  ClassSessionStore? _session;
  ProvaStore? _provaStore;
  Timer? _notifyTimer;
  int _ultimoOnline = -1;

  // Imagens pedidas (câmera/tela) aguardando chegar por /snapshot. A chave
  // leva o tipo: uma captura de tela não pode resolver um pedido de foto.
  final Map<String, Completer<Uint8List?>> _fotoPendente = {};

  // Visão da turma no telão: debounce de push + heartbeat + dedupe.
  Timer? _classViewTimer;
  Timer? _classViewHeartbeat;
  Timer? _versaoTimer;
  String? _classViewFingerprint;

  /// Estado de inicialização (a UI observa; start() não lança).
  bool iniciando = true;
  String? erroDeConexao;

  /// Notificações com som (alerta/bloqueio). Sincronizado pelo root a partir
  /// das preferências (Ajustes).
  bool notificarSites = true;

  /// Injetado pelo root (main.dart) antes do start().
  NotificationService? notificacoes;

  /// Workspace da escola (uid do fundador). Setado pelo root a partir das
  /// prefs ANTES do start(); mudanças (criar/entrar) são persistidas pelo
  /// root via listener (padrão do pcProfessorId).
  String? schoolUid;

  /// Workspace ativo?
  bool get workspaceAtivo => schoolUid != null;

  /// Este celular está na escola, mas o e-mail ainda não foi liberado pelo
  /// fundador: nada da escola sobe até "Tentar de novo" passar.
  bool naoLiberadoNaEscola = false;

  /// Só o fundador cuida de "Professores da escola".
  bool get souFundador =>
      schoolUid != null && _usuarioAtual?.uid == schoolUid;

  /// Injetado pelo root: guarda o dia da última poda do arquivo.
  PrefsStore? prefs;

  SchoolSync? _schoolSync;
  AulaLocks? _aulaLocks;
  Timer? _lockHeartbeat;

  String? _pcProfessorId;

  /// deviceId do "PC do professor" (telão): fora dos broadcasts, sem regras
  /// de bloqueio, sem histórico/alerta/notificações.
  String? get pcProfessorId => _pcProfessorId;

  bool ehPcProfessor(String deviceId) => deviceId == _pcProfessorId;

  /// PC do professor marcado e online?
  bool get pcProfessorOnline {
    final id = _pcProfessorId;
    if (id == null) return false;
    final s = _transport?.registry.byId(id);
    return s != null && isOnline(s);
  }

  /// Marca/desmarca (null) o PC do professor. Redistribui as regras dos
  /// afetados: o marcado recebe snapshot vazio (sem bloqueios — links de
  /// alunos precisam abrir no telão); o desmarcado volta ao bloqueio integral.
  void marcarPcProfessor(String? deviceId) {
    final anterior = _pcProfessorId;
    if (anterior == deviceId) return;
    _pcProfessorId = deviceId;
    _transport?.pcProfessorId = deviceId;
    _transport?.registry.pcProfessorId = deviceId;
    if (anterior != null) _distribuirRegrasPara(anterior);
    if (deviceId != null) _distribuirRegrasPara(deviceId);
    // Visão da turma: o antigo telão perde o snapshot (deixa de se considerar
    // telão); o novo recebe um imediatamente.
    if (anterior != null) {
      _classViewFingerprint = null;
      _transport?.clearState(anterior, 'classview').catchError((_) {});
    }
    if (deviceId != null) _pushClassView(force: true);
    notifyListeners();
  }

  /// Mensagem individual: agora é a conversa (chat). Mantido para a tela
  /// antiga até ela trocar "Enviar mensagem" por "Conversar". Null = ok.
  Future<String?> enviarMensagem(String deviceId, String texto) =>
      enviarChat(deviceId, texto);

  /// Abre uma URL só no PC do professor (ex.: link do histórico de um aluno).
  void abrirNoPcProfessor(String url) {
    final id = _pcProfessorId;
    if (id == null) return;
    _transport?.sendCommand(id, buildOpenUrl(url));
  }

  /// Pede 1 foto da webcam do PC e espera a imagem (cifrada) voltar por
  /// /snapshot (timeout ~20s). null = falhou/timeout: câmera bloqueada, sem a
  /// policy VideoCaptureAllowedUrls, ou PC offline.
  Future<Uint8List?> tirarFotoCamera(String deviceId) => _pedirImagem(
        deviceId,
        buildCaptureCamera(),
        MessageType.cameraSnapshot,
      );

  /// Pede 1 captura da tela do PC. Só o agente do Celita OS responde; num
  /// Chromebook comum volta null (o cliente acka `tipo_desconhecido`), e
  /// também null quando ninguém está logado na conta de aluno.
  Future<Uint8List?> tirarFotoTela(String deviceId) => _pedirImagem(
        deviceId,
        buildCaptureScreen(),
        MessageType.screenSnapshot,
      );

  Future<Uint8List?> _pedirImagem(
    String deviceId,
    Map<String, dynamic> comando,
    String tipoResposta,
  ) {
    final t = _transport;
    if (t == null) return Future.value(null);
    final chave = '$deviceId|$tipoResposta';
    _fotoPendente.remove(chave)?.complete(null); // cancela pedido anterior
    final c = Completer<Uint8List?>();
    _fotoPendente[chave] = c;
    t.sendCommand(deviceId, comando);
    return c.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _fotoPendente.remove(chave);
        return null;
      },
    );
  }

  // ---- Visão da turma (telão) ------------------------------------------------------
  // O telão não decifra os reports dos outros PCs (E2E por par); o app agrega
  // e re-cifra um snapshot em state/classview — ver docs/protocolo.md.

  /// Mesma lista da aba Aula: fora de aula todos os pareados; em aula só os
  /// vinculados. O telão nunca aparece na própria lista (_devicesAlvo).
  List<ClassViewPc> _montarClassView() {
    final registry = _transport?.registry;
    if (registry == null) return const [];
    final pcs = <ClassViewPc>[];
    for (final id in _devicesAlvo()) {
      final s = registry.byId(id);
      if (s == null) continue;
      final aba = s.abaAtiva;
      pcs.add(
        ClassViewPc(
          nome: nomeDe(s),
          online: isOnline(s),
          aluno: alunoDe(id),
          abaTitulo: aba?.title,
          abaDominio: dominioDaUrl(aba?.url),
          alerta: s.alerta,
        ),
      );
    }
    return pcs;
  }

  /// Empurra (ou pula, se nada mudou) o snapshot para o telão. Best-effort:
  /// permission-denied (rules antigas) não pode derrubar o app.
  Future<void> _pushClassView({bool force = false}) async {
    final transport = _transport;
    final id = _pcProfessorId;
    if (transport == null || id == null) return;
    if (transport.registry.byId(id) == null) return; // telão fora do registry
    final cmd = buildSetClassView(
      rev: _proximoRev(),
      aulaAtiva: aulaAtiva,
      turma: turmaDaAula,
      pcs: _montarClassView(),
    );
    final fp = classViewFingerprint(cmd);
    if (!force && fp == _classViewFingerprint) return;
    try {
      await transport.setStateOne(id, cmd);
      _classViewFingerprint = fp;
    } catch (e) {
      debugPrint('classview: push falhou (rules antigas?): $e');
    }
  }

  Future<void> start() async {
    if (_transport != null) return; // idempotente (retry não duplica listeners)
    try {
      final teacher = await KeyStore.loadOrCreate();
      _names = await NameStore.load();
      _units = await UnitStore.load();
      _rules = await RulesStore.load();
      _favorites = await FavoritesStore.load();
      _home = await HomeStore.load();
      _wallpaper = await WallpaperStore.load();
      _students = await StudentsStore.load();
      _session = await ClassSessionStore.load();
      _provaStore = await ProvaStore.load();

      // Auth anônima: o uid identifica este professor nas Security Rules.
      // Persiste entre execuções; some só se o app for reinstalado (recovery:
      // aluno desvincula pelo popup e re-escaneia).
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      if (user == null) {
        throw StateError('auth_anonima_falhou');
      }
      // Escola fechada: sem liberação não sobe nada da escola (nem o roster).
      // Não sai da escola nem mexe na keypair — o fundador pode liberar depois.
      if (schoolUid != null && !await _liberadoNaEscola(user)) {
        naoLiberadoNaEscola = true;
        erroDeConexao = textoNaoLiberado(user.email ?? emailGoogle);
        return;
      }
      naoLiberadoNaEscola = false;

      final transport = FirebaseTransport(
        teacher: teacher,
        teacherUid: user.uid,
        schoolUid: schoolUid,
        teacherName: deviceName,
      );
      transport.comandosDeEstado = _comandosDeEstado;
      transport.onSnapshot = (deviceId, tipo, jpeg) {
        _fotoPendente.remove('$deviceId|$tipo')?.complete(jpeg);
      };
      transport.registry.onChange = _scheduleNotify;
      transport.registry.avaliarAlerta = _avaliarAlerta;
      transport.registry.onNovosEventos = _onNovosEventos;
      transport.onAcessoNegado = _acessoNegadoNaEscola;
      transport.pcProfessorId = _pcProfessorId;
      transport.registry.pcProfessorId = _pcProfessorId;
      // Recursos de turma: acks e `aplicado` (entrega e balões), up/ (chat,
      // pedidos, mão) com destino pela reserva de aula.
      transport.onAck = _aoAck;
      transport.registry.onAplicado = _aoAplicado;
      transport.destinoDoUp = _destinoDoUp;
      transport.onUp = _aoUp;
      transport.onUpRemovido = _aoUpRemovido;
      transport.onUpSilenciado = _aoUpSilenciado;
      // Itens do up/ com push id anterior a isto são reidratação: voltam como
      // não lidos, sem tocar o celular. O push id está no relógio do
      // servidor: quando o offset chegar, o corte passa para ele também.
      final inicioLocal = DateTime.now().millisecondsSinceEpoch;
      _upInicioMs = inicioLocal;
      await transport.start();
      _transport = transport;
      unawaited(
        transport.relogioPronto.then((_) {
          final decorrido = DateTime.now().millisecondsSinceEpoch - inicioLocal;
          _upInicioMs = transport.nowServer().millisecondsSinceEpoch - decorrido;
        }),
      );

      // Sync dos stores compartilhados (workspace): listeners nos 4 stores da
      // escola; mudanças remotas recarregam o store local correspondente.
      if (schoolUid != null) {
        _schoolSync = SchoolSync(
          crypto: await schoolCryptoFrom(teacher),
          nowServerMs: () => transport.nowServer().millisecondsSinceEpoch,
          database: FirebaseDatabase.instance,
        );
        _schoolSync!.onRemoto = _aplicarStoreRemoto;
        _schoolSync!.start();
        // Travas de aula: 1 PC em 1 aula por vez, entre professores.
        _aulaLocks = AulaLocks(
          meuUid: user.uid,
          crypto: _schoolSync!.crypto,
          nowServerMs: () => transport.nowServer().millisecondsSinceEpoch,
        );
        _aulaLocks!.onChange = () {
          // Reserva mudou: up/ guardado de PC que ficou livre (ou meu) é lido.
          transport.reavaliarUpIgnorados();
          _scheduleNotify();
        };
        _aulaLocks!.start();
        unawaited(_podarArquivo(transport));
      }
      // Heartbeat da reserva (escola) + renovação de "Olhos em mim" e do modo
      // prova (os dois modos): 5 min, o mesmo timer.
      _lockHeartbeat ??= Timer.periodic(kRenovacao, (_) {
        if (aulaAtiva) _aulaLocks?.heartbeat();
        unawaited(_renovarTurma());
        // Reserva de outro professor vence pelo relógio (15 min sem
        // heartbeat), sem evento em /school/aulas: o up/ guardado do PC que
        // ficou livre é lido aqui.
        _transport?.reavaliarUpIgnorados();
      });

      // Heartbeat da visão da turma: mantém o "atualizado há Xs" do telão
      // vivo e propaga online→offline (derivado de lastSeen, não gera evento).
      _buscarVersaoPublicada();
      _versaoTimer ??= Timer.periodic(const Duration(minutes: 30), (_) => _buscarVersaoPublicada());

      _classViewHeartbeat ??= Timer.periodic(
        const Duration(seconds: 60),
        (_) => _pushClassView(force: true),
      );

      // Histórico de aulas: cifrado com chave derivada da keypair do
      // professor; re-anexa à sessão aberta se o app fechou no meio da aula.
      final hCrypto = await historyCryptoFrom(teacher);
      // Workspace: histórico compartilhado vive no nó do FUNDADOR (schoolUid
      // == uid dele; a keypair da escola é a dele) — migração zero.
      _history = HistoryStore(teacherUid: schoolUid ?? user.uid, crypto: hCrypto);
      _backup = BackupStore(
        uid: user.uid,
        historyCrypto: hCrypto,
        // Workspace: turmas/regras/números/nomes vivem em /school/stores;
        // o backup pessoal carrega só o que é por professor.
        arquivos: workspaceAtivo
            ? const ['favorites.json', 'app_prefs.json']
            : kArquivosDeBackup,
      );
      // Workspace: backup de stores pessoais sempre ativo (sem PIN — a chave
      // vem da escola); modo isolado: ativo se a keypair já subiu (PIN).
      backupAtivo = workspaceAtivo || await _backup!.existeNaNuvem();
      final session = _session;
      if (session != null && session.ativa) {
        await _history!.abrirSessao(
          session.turma,
          session.inicio.millisecondsSinceEpoch,
        );
      }
      await iniciarServicoAula();
      erroDeConexao = null;
    } catch (e) {
      // Só erros de config/auth chegam aqui; queda de rede transitória o
      // FlutterFire reconecta sozinho. O erro cru fica só no log.
      debugPrint('[CdA] start falhou: $e');
      erroDeConexao = 'Sem conexão com a internet. Tente de novo.';
    } finally {
      iniciando = false;
      notifyListeners();
    }
  }

  // ---- Conta Google + backup (troca de celular) ------------------------------------

  /// Web client id do projeto (google-services.json, oauth type 3).
  static const _kWebClientId =
      '305628431439-tco3ac2lgab00tu09pnesvhr9l52kbho.apps.googleusercontent.com';
  bool _googleInit = false;

  User? get _usuarioAtual {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null; // Firebase não inicializado (ex.: teste de widget)
    }
  }

  bool get logadoComGoogle =>
      _usuarioAtual?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  String? get emailGoogle => _usuarioAtual?.providerData
      .where((p) => p.providerId == 'google.com')
      .map((p) => p.email)
      .firstOrNull;

  /// Entra com Google. Retorna:
  /// - 'linked': conta Google vinculada ao professor atual (uid mantido —
  ///   nada muda, só habilita o backup);
  /// - 'switched': a conta Google já era usada em outro celular — o app agora
  ///   está no uid antigo; restaurar o backup (PIN) e REINICIAR;
  /// - 'erro:<detalhe>' em falhas (inclui cancelamento).
  Future<String> entrarComGoogle() async {
    try {
      if (!_googleInit) {
        await GoogleSignIn.instance.initialize(serverClientId: _kWebClientId);
        _googleInit = true;
      }
      final conta = await GoogleSignIn.instance.authenticate();
      final idToken = conta.authentication.idToken;
      if (idToken == null) return 'erro:sem_token';
      final cred = GoogleAuthProvider.credential(idToken: idToken);
      final auth = FirebaseAuth.instance;
      try {
        // Vincula à conta anônima atual: o uid NÃO muda (pareamentos e
        // histórico continuam valendo).
        await auth.currentUser!.linkWithCredential(cred);
        notifyListeners();
        return 'linked';
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use' ||
            e.code == 'email-already-in-use') {
          // Conta já existe (outro celular): assume o uid antigo.
          await auth.signInWithCredential(cred);
          notifyListeners();
          return 'switched';
        }
        return 'erro:${e.code}';
      }
    } catch (e) {
      return 'erro:$e';
    }
  }

  /// QR de login do app do Celita OS: entrega id_token fresco + chave do
  /// professor ao computador, que vira o mesmo professor deste celular.
  Future<String?> entregarLoginPorQr(QrLoginPayload qr) async {
    if (!logadoComGoogle) {
      return 'Entre com Google (em Ajustes) para entregar o login ao computador.';
    }
    try {
      if (!_googleInit) {
        await GoogleSignIn.instance.initialize(serverClientId: _kWebClientId);
        _googleInit = true;
      }
      var conta = await GoogleSignIn.instance.attemptLightweightAuthentication();
      conta ??= await GoogleSignIn.instance.authenticate();
      final idToken = conta.authentication.idToken;
      if (idToken == null) return 'O Google não devolveu o token — tente de novo.';
      final keys = await KeyStore.lerBruto();
      if (keys == null) return 'Chave local ainda não existe — reabra o app.';
      final payload = await LoginHandoff.montar(
        qr: qr,
        idToken: idToken,
        keys: keys,
        teacherName: deviceName,
        schoolUid: schoolUid,
      );
      await LoginHandoff.entregar(qr, payload);
      return null;
    } catch (e) {
      debugPrint('[CdA] entregar login: $e');
      return 'Não foi possível entrar no computador agora. Tente de novo.';
    }
  }

  /// Ativa o backup: keypair cifrada pelo PIN + stores. Exige login Google.
  Future<void> ativarBackup(String pin) async {
    final b = _backup;
    if (b == null) return;
    await b.subirKeypair(pin);
    await b.subirStores();
    backupAtivo = true;
    notifyListeners();
  }

  /// Força um backup dos stores agora (a keypair já está lá).
  Future<void> backupAgora() async => _backup?.subirStores();

  /// Existe backup na conta atualmente logada? (uso pós-'switched')
  Future<bool> temBackupNaNuvem() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    // Pós-switch o _backup aponta pro uid velho — consulta direta:
    try {
      final v = await FirebaseDatabase.instance
          .ref('backup/$uid/keypair')
          .get();
      return v.value is String;
    } catch (_) {
      return false;
    }
  }

  /// Restaura keypair (PIN) + stores da conta logada para o disco local.
  /// Retorna null em sucesso (REINICIAR o app) ou mensagem de erro.
  Future<String?> restaurarBackup(String pin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Entre com o Google primeiro.';
    try {
      await BackupStore.restaurar(uid: uid, pin: pin);
      return null;
    } on PinIncorretoException {
      return 'PIN incorreto.';
    } catch (e) {
      debugPrint('[CdA] restaurar backup: $e');
      return 'Não foi possível restaurar o backup. Confira o PIN e tente de novo.';
    }
  }

  // Sync automático dos stores: qualquer mudança de estado agenda um backup
  // (debounce 2 min) quando o backup está ativo. O mesmo funil agenda o push
  // da visão da turma (debounce 1,5 s): reports, vínculos, iniciar/encerrar
  // aula, renomes — tudo passa por notifyListeners.
  @override
  void notifyListeners() {
    if (backupAtivo && _backup != null && _backupTimer == null) {
      _backupTimer = Timer(const Duration(minutes: 2), () {
        _backupTimer = null;
        _backup?.subirStores();
      });
    }
    if (_pcProfessorId != null && _classViewTimer == null) {
      _classViewTimer = Timer(const Duration(milliseconds: 1500), () {
        _classViewTimer = null;
        _pushClassView();
      });
    }
    super.notifyListeners();
  }

  // ---- Workspace da escola ---------------------------------------------------------

  Future<void> _reiniciarTransporte() async {
    await _aulaLocks?.stop();
    _aulaLocks = null;
    await _schoolSync?.stop();
    _schoolSync = null;
    await _transport?.stop();
    _transport = null;
    iniciando = true;
    notifyListeners();
    await start();
  }

  /// Um store da escola mudou (outro professor editou): recarrega o local.
  Future<void> _aplicarStoreRemoto(String k) async {
    switch (k) {
      case 'turmas':
        _students = await StudentsStore.load();
      case 'rules':
        _rules = await RulesStore.load();
        _redistribuirRegrasRemotas();
      case 'units':
        _units = await UnitStore.load();
      case 'names':
        _names = await NameStore.load();
      case 'prova':
        _provaStore = await ProvaStore.load();
        unawaited(_redistribuirProva());
    }
    notifyListeners();
  }

  /// Fundador (1 tap): publica a keypair local como a chave da escola e migra
  /// o roster. PCs pareados continuam valendo — a chave não muda.
  Future<String?> criarWorkspace() async {
    final user = _usuarioAtual;
    if (user == null || !logadoComGoogle) {
      return 'Entre com Google primeiro (em Conta).';
    }
    try {
      await user.getIdToken(true); // claim email fresco p/ as rules
      final erro = await SchoolKeys().publicar(user.uid);
      if (erro != null) return erro;
      // Seed do roster da escola = meus PCs atuais.
      final db = FirebaseDatabase.instance;
      final roster = (await db.ref('teachers/${user.uid}/devices').get()).value;
      if (roster is Map && roster.isNotEmpty) {
        await db
            .ref('school/devices')
            .update({for (final k in roster.keys) '$k': true});
      }
      schoolUid = user.uid;
      await _reiniciarTransporte();
      // Seed: sobe os stores locais como os da escola.
      await _schoolSync?.pushTodos();
      return null;
    } catch (e) {
      debugPrint('[CdA] criar escola: $e');
      return 'Não foi possível acessar a escola agora. Tente de novo.';
    }
  }

  /// Professor novo: login Google, adota a chave da escola e entra.
  /// A UI deve avisar antes que PCs pareados com a chave própria vão exigir
  /// re-pareamento (a keypair local é sobrescrita).
  Future<String?> entrarNoWorkspace() async {
    try {
      if (!logadoComGoogle) {
        final r = await entrarComGoogle();
        if (r.startsWith('erro:')) {
          debugPrint('[CdA] login Google: ${r.substring(5)}');
          return 'Não foi possível entrar com o Google. Tente de novo.';
        }
      }
      final user = _usuarioAtual;
      if (user == null) return 'Não foi possível entrar com o Google. Tente de novo.';
      await user.getIdToken(true);
      const semEscola =
          'A escola ainda não foi criada — peça ao professor fundador.';
      final chaves = SchoolKeys();
      final fundador = await chaves.schoolUidPublicado();
      if (fundador == null) return semEscola;
      if (user.uid != fundador) {
        final email = user.email ?? emailGoogle;
        if (email == null || !await SchoolMembers().liberado(email)) {
          return textoNaoLiberado(email);
        }
      }
      final escola = await chaves.baixar();
      if (escola == null) return semEscola;
      final minhas = await KeyStore.lerBruto();
      if (minhas != escola.keys) await SchoolKeys().adotar(escola);
      schoolUid = escola.schoolUid;
      await _reiniciarTransporte();
      return null;
    } catch (e) {
      debugPrint('[CdA] entrar na escola: $e');
      return 'Não foi possível acessar a escola agora. Tente de novo.';
    }
  }

  Future<bool> _liberadoNaEscola(User user) async {
    if (user.uid == schoolUid) return true;
    final email = user.email ?? emailGoogle;
    if (email == null) return false;
    return liberadoAoAbrir(() => SchoolMembers().liberado(email));
  }

  // O fundador tirou o e-mail da lista com o app aberto: as leituras da
  // escola passam a ser negadas. Para tudo e mostra o texto único.
  void _acessoNegadoNaEscola() {
    if (schoolUid == null || naoLiberadoNaEscola) return;
    naoLiberadoNaEscola = true;
    erroDeConexao = textoNaoLiberado(_usuarioAtual?.email ?? emailGoogle);
    unawaited(() async {
      await _aulaLocks?.stop();
      _aulaLocks = null;
      await _schoolSync?.stop();
      _schoolSync = null;
      await _transport?.stop();
      _transport = null;
      notifyListeners();
    }());
    notifyListeners();
  }

  // Reserva da retenção do agente: 1x por dia por celular, apaga de hoje−45
  // a hoje−15 em cada PC da escola. O agente é quem poda de verdade.
  Future<void> _podarArquivo(FirebaseTransport transport) async {
    final p = prefs;
    if (p == null) return;
    // Sem o relógio do servidor não poda hoje: um celular com a data
    // adiantada apagaria dias ainda dentro dos 15.
    try {
      await transport.relogioPronto.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return;
    }
    final agora = transport.nowServer().millisecondsSinceEpoch;
    final hoje = dayOf(agora);
    if (p.ultimaPodaArquivo == hoje) return;
    try {
      final roster =
          (await FirebaseDatabase.instance.ref('school/devices').get()).value;
      if (roster is Map && roster.isNotEmpty) {
        await ArchiveStore.prune(roster.keys.map((k) => '$k'), agora);
      }
      await p.setUltimaPodaArquivo(hoje);
    } catch (e) {
      debugPrint('[CdA] poda do arquivo falhou: $e');
    }
  }

  /// Agora (ms) no relógio do servidor: é por ele que se escolhe o dia.
  int agoraServidorMs() =>
      (_transport?.nowServer() ?? DateTime.now()).millisecondsSinceEpoch;

  /// Arquivo de 15 dias de um PC (histórico + fotos), com a chave dele.
  ArchiveStore? arquivoDe(String deviceId) {
    final s = pcPorId(deviceId);
    if (s == null) return null;
    return ArchiveStore(deviceId: deviceId, crypto: s.crypto);
  }

  /// Retry manual após erro de inicialização.
  Future<void> tentarNovamente() async {
    if (_transport != null) return;
    iniciando = true;
    erroDeConexao = null;
    notifyListeners();
    await start();
  }

  /// Atualiza o nome exibido no popup da extensão (vale para os PRÓXIMOS
  /// pareamentos; PCs já pareados mantêm o nome antigo até re-parear).
  void atualizarNomeProfessor(String nome) {
    final n = nome.trim();
    deviceName = n.isEmpty ? 'Professor' : n;
    _transport?.teacherName = deviceName;
    notifyListeners();
  }

  // Comandos de estado vigentes (gravados em state/* a cada pareamento):
  // set_rules SEMPRE (mesmo vazio, para limpar regras antigas no cliente),
  // já descontando as liberações da aula para AQUELE PC;
  // set_unit se o device já tem número (re-pareamento reescreve state/unit
  // com a chave nova; 1º pareamento sai sem — o bind.numero cobre).
  List<Map<String, dynamic>> _comandosDeEstado(String deviceId) {
    final numero = _units?.numeroDe(deviceId);
    final naTurma = _alvoTurma().contains(deviceId);
    return [
      if (_rules != null) _setRulesPara(deviceId),
      if (numero != null) buildSetUnit(rev: _proximoRev(), numero: numero),
      // Papel de parede vigente: sem isto um PC pareado depois nunca o recebe.
      if (_wallpaper?.hash != null) buildSetWallpaper(_wallpaper!.hash!),
      // Re-pareamento de PC da aula com trava/prova ligadas: chave nova,
      // estado reescrito (o envelope antigo ficou ilegível para o PC).
      if (naTurma && (_session?.trava.on ?? false)) _setLockLigado(),
      if (naTurma && (_session?.prova.on ?? false))
        _setExamPara(deviceId, on: true, rev: _proximoRev()),
    ];
  }

  // ---- Número da unidade (edição pós-pareamento) -----------------------------------

  /// Número da unidade de um PC (null = pareado antes do app 0.13).
  int? numeroDe(String deviceId) => _units?.numeroDe(deviceId);

  /// Muda o número da unidade. Número já ocupado por outro PC = os dois
  /// TROCAM (nunca duplica). Retorna null (ok) ou mensagem de erro.
  Future<String?> alterarNumeroUnidade(String deviceId, int numero) async {
    final units = _units;
    if (units == null) return 'Ainda carregando — tente de novo.';
    if (numero < 1 || numero > 9999) return 'Use um número de 1 a 9999.';
    final numeroAntigo = units.numeroDe(deviceId);
    if (numeroAntigo == numero) return null; // nada a fazer
    // Calcular ANTES de gravar (definir muda o resultado de proximo()).
    final donoAtual = units.deviceIdDoNumero(numero);
    // Se o PC editado ainda não tinha número, o dono deslocado vai pro fim
    // da fila — nunca fica duplicado.
    final numeroParaDono = numeroAntigo ?? units.proximo();

    await units.definir(deviceId, numero);
    _enviarUnit(deviceId, numero);
    if (donoAtual != null && donoAtual != deviceId) {
      await units.definir(donoAtual, numeroParaDono);
      _enviarUnit(donoAtual, numeroParaDono);
    }
    _schoolSync?.push('units');
    notifyListeners();
    return null;
  }

  /// Label otimista no app + set_unit em state/unit (best-effort: extensão
  /// < 0.4.6 ignora; o meta/label que ela devolve re-sincroniza o nome).
  void _enviarUnit(String deviceId, int numero) {
    final s = pcPorId(deviceId);
    if (s != null) s.label = 'Unidade $numero';
    _transport
        ?.setStateOne(deviceId, buildSetUnit(rev: _proximoRev(), numero: numero))
        .catchError((e) => debugPrint('set_unit falhou: $e'));
  }

  /// set_rules de um PC: bloqueios da casa − liberações dele; alertas todos.
  /// PC do professor: sem regra nenhuma (o telão precisa abrir qualquer link).
  Map<String, dynamic> _setRulesPara(String deviceId) {
    if (deviceId == _pcProfessorId) {
      return buildSetRules(const [], rev: _proximoRev(), filtros: Filtros.nenhum);
    }
    return buildSetRules(
      _rules?.regras ?? const [],
      rev: _proximoRev(),
      liberados: _session?.excecoesDe(deviceId) ?? const {},
      filtros: filtros,
    );
  }

  // O guard do cliente exige rev estritamente crescente; como o snapshot de
  // um PC muda também por liberação (não só por edição das regras), cada
  // distribuição usa um rev novo e monotônico.
  int _ultimoRev = 0;
  int _proximoRev() {
    // Relógio do SERVIDOR: revs de rules/classview/unit ficam ordenados
    // também entre celulares de professores diferentes (workspace).
    final agora = (_transport?.nowServer() ?? DateTime.now()).millisecondsSinceEpoch;
    _ultimoRev = agora > _ultimoRev ? agora : _ultimoRev + 1;
    return _ultimoRev;
  }

  // Domínio da primeira aba que casa regra `alert` OU `block` (aba bloqueada
  // ainda aberta = enforcement falhou — o professor precisa ver). Padrões
  // liberados para o PC nesta aula não geram alerta.
  String? _avaliarAlerta(String deviceId, List<TabInfo> tabs) {
    final regras = _rules?.regras;
    if (regras == null || regras.isEmpty) return null;
    final liberados = _session?.excecoesDe(deviceId) ?? const <String>{};
    for (final t in tabs) {
      final r = acharRegra(regras, t.url);
      if (r != null && !liberados.contains(r.pattern)) {
        try {
          return Uri.parse(t.url).host;
        } catch (_) {
          return r.pattern;
        }
      }
    }
    return null;
  }

  // Eventos de navegação inéditos: notifica com som quando um PC acessa site
  // de "Alertar" ou TENTA um bloqueado (a tentativa chega no histórico — a
  // extensão registra antes do redirect). Liberações da aula não notificam.
  void _onNovosEventos(String deviceId, List<NavEvent> novos) {
    // Histórico persistente: só de PCs com aluno vinculado numa aula ativa
    // (TODOS os eventos, não só os com regra). PC do professor nunca emite.
    if (aulaAtiva) {
      final aluno = alunoDe(deviceId);
      if (aluno != null) _history?.registrar(aluno, novos);
    }

    final notifs = notificacoes;
    if (!notificarSites || notifs == null) return;
    final regras = _rules?.regras ?? const <DomainRule>[];
    final liberados = _session?.excecoesDe(deviceId) ?? const <String>{};
    final s = _transport?.registry.byId(deviceId);
    final nomePc = (s != null ? alunoDe(deviceId) ?? nomeDe(s) : deviceId);
    for (final e in novos) {
      final r = regras.isEmpty ? null : acharRegra(regras, e.url);
      final porRegra = r != null && !liberados.contains(r.pattern);
      // Filtros (Shorts, IA...) não viram regra aqui: a extensão marca a tentativa.
      final filtro = descricaoBloqueio(e.bloqueio);
      if (!porRegra && filtro == null) continue;
      String dominio;
      try {
        dominio = Uri.parse(e.url).host;
      } catch (_) {
        dominio = r?.pattern ?? e.url;
      }
      if (!porRegra) dominio = '$filtro ($dominio)';
      final bloqueado = !porRegra || r.action == RuleAction.block;
      final futuro = bloqueado
          ? notifs.notificarBloqueado(
              deviceId: deviceId,
              ts: e.ts,
              pc: nomePc,
              dominio: dominio,
            )
          : notifs.notificarAlerta(
              deviceId: deviceId,
              ts: e.ts,
              pc: nomePc,
              dominio: dominio,
            );
      // Mesma decisão de throttle vale pro telão: se disparou no celular,
      // apita também no PC do professor (se marcado e online).
      futuro.then((disparou) {
        if (disparou && pcProfessorOnline) {
          _transport?.sendCommand(
            _pcProfessorId!,
            buildShowMessage(
              bloqueado ? '🚫 $nomePc' : '⚠ $nomePc',
              bloqueado ? 'Tentou acessar $dominio' : 'Acessou $dominio',
            ),
          );
        }
      });
    }
  }

  // Coalesce: presença/report da turma toda dispara muitos onChange por
  // segundo; a UI só precisa de ~4 quadros/s.
  void _scheduleNotify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      _atualizarNotificacao();
      notifyListeners();
    });
  }

  void _atualizarNotificacao() {
    final online = pcs.where(isOnline).length;
    if (online != _ultimoOnline) {
      _ultimoOnline = online;
      atualizarNotificacaoAula('$online PC(s) conectados');
    }
  }

  List<PcSession> get pcs => _transport?.registry.all ?? const [];

  PcSession? pcPorId(String deviceId) => _transport?.registry.byId(deviceId);

  /// PC ainda carregando (app abrindo, roster a caminho ou rehidratando).
  bool carregandoPc(String deviceId) =>
      iniciando || (_transport?.aguardandoPc(deviceId) ?? false);

  bool isOnline(PcSession s) =>
      s.online(_transport?.nowServer() ?? DateTime.now());

  /// Nome dado pelo professor, ou o label do aparelho (renomeável no popup).
  String nomeDe(PcSession s) => _names?.nameOf(s.deviceId) ?? s.label;

  /// Nome + " (versão do Celita OS)" para as listas; nunca é gravado como nome.
  String rotuloDe(PcSession s) =>
      nomeComVersao(nomeDe(s), s.versaoOs, desatualizado: desatualizado(s));

  // ---- Versão do Celita OS -----------------------------------------------------

  /// Última versão publicada no canal de atualização (null = ainda não lida).
  String? versaoPublicada;

  Future<void> _buscarVersaoPublicada() async {
    final v = await buscarVersaoPublicada();
    if (v != null && v != versaoPublicada) {
      versaoPublicada = v;
      notifyListeners();
    }
  }

  bool desatualizado(PcSession s) => celitaDesatualizado(s.versaoOs, s.versaoExt, versaoPublicada);

  /// PCs ligados agora com o Celita mais velho que o publicado.
  List<PcSession> get desatualizadosOnline => [
        for (final s in _transport?.registry.all ?? const <PcSession>[])
          if (isOnline(s) && desatualizado(s)) s,
      ];

  /// Pede ao PC para atualizar o sistema agora. null = pedido enviado.
  Future<String?> atualizarPc(String deviceId) async {
    final transport = _transport;
    final s = transport?.registry.byId(deviceId);
    if (transport == null || s == null) return 'Ainda conectando — tente de novo.';
    if (!isOnline(s)) return 'O PC está desligado.';
    if (!temCelita(s.versaoExt)) return 'Só os PCs com Celita OS se atualizam pelo app.';
    await transport.sendCommand(deviceId, buildAtualizar());
    return null;
  }

  /// Pede atualização a todos os desatualizados ligados; devolve quantos.
  Future<int> atualizarDesatualizados() async {
    var n = 0;
    for (final s in desatualizadosOnline) {
      if (await atualizarPc(s.deviceId) == null) n++;
    }
    return n;
  }

  /// Salva o nome do aluno para este PC (vazio remove).
  Future<void> renomear(String deviceId, String nome) async {
    await _names?.setName(deviceId, nome);
    _schoolSync?.push('names');
    notifyListeners();
  }

  // ---- Pareamento (QR) ----------------------------------------------------------

  /// Processa o conteúdo de um QR escaneado. Retorna null em caso de sucesso
  /// ou uma mensagem de erro (PT-BR) para a UI.
  Future<String?> parearComQr(String raw) async {
    final qr = QrPairPayload.parse(raw);
    if (qr == null) return 'QR inválido — use o QR do popup da extensão.';
    final transport = _transport;
    if (transport == null) return 'Ainda conectando ao Firebase — tente de novo.';
    try {
      // Número da unidade: reusa o do device (re-pareamento) ou o próximo da
      // sequência; só persiste depois que o bind foi aceito pelas rules.
      final numero = _units?.candidatoPara(qr.deviceId);
      await transport.pairDevice(qr, numero: numero);
      if (numero != null) {
        await _units?.definir(qr.deviceId, numero);
        _schoolSync?.push('units');
      }
      // Visão da turma: re-pareamento reescreve (telão) ou limpa (demais) o
      // state/classview — mata envelope órfão de professor/chave anterior
      // (a extensão não tem permissão de deletar state/*).
      if (qr.deviceId == _pcProfessorId) {
        _pushClassView(force: true);
      } else {
        transport.clearState(qr.deviceId, 'classview').catchError((_) {});
      }
      _scheduleNotify();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'QR expirado ou PC vinculado a outro professor — '
            'gere um QR novo no popup da extensão.';
      }
      debugPrint('[CdA] parear: ${e.code} ${e.message}');
      return 'Não foi possível conectar este computador. Tente de novo.';
    } catch (e) {
      debugPrint('[CdA] parear: $e');
      return 'Não foi possível conectar este computador. Tente de novo.';
    }
  }

  /// Desfaz o vínculo de um PC (a extensão volta a exibir o QR).
  Future<void> esquecerPc(String deviceId) async {
    if (deviceId == _pcProfessorId) marcarPcProfessor(null);
    await _transport?.forgetDevice(deviceId);
    notifyListeners();
  }

  // ---- Comandos ---------------------------------------------------------------

  /// PCs alvo dos comandos de turma: durante aula ativa, só os vinculados a
  /// aluno; fora de aula, todos. O PC do professor nunca entra.
  List<String> _devicesAlvo() {
    final registry = _transport?.registry;
    final locks = _aulaLocks;
    return alvoDeBroadcast(
      aulaAtiva: aulaAtiva,
      vinculados: _session?.vinculos.keys ?? const [],
      todos: (registry?.all ?? const []).map((s) => s.deviceId),
      pcProfessorId: _pcProfessorId,
      travadosPorOutros: locks == null
          ? const {}
          : (registry?.all ?? const [])
              .map((s) => s.deviceId)
              .where(locks.travadoPorOutro)
              .toSet(),
    );
  }

  /// Quantos PCs um comando de turma vai atingir agora.
  int get pcsAlvoCount => _devicesAlvo().length;

  /// Aula em que o PC está agora, para a home agrupar por seções:
  /// - minha aula ativa com aluno vinculado → (minha: true, eu, minha turma);
  /// - trava viva de OUTRO professor → (false, nome dele, turma dele);
  /// - sem aula (inclui trava MINHA órfã de aula já encerrada) → null.
  ({bool minha, String professor, String? turma})? aulaDoPc(String deviceId) {
    if (aulaAtiva && alunoDe(deviceId) != null) {
      return (minha: true, professor: deviceName, turma: turmaDaAula);
    }
    final t = _aulaLocks?.travaVivaDe(deviceId);
    if (t == null) return null;
    final meuUid = _usuarioAtual?.uid;
    if (t.uid == meuUid) return null; // minha trava sem aula ativa = órfã
    return (
      minha: false,
      professor: t.professor ?? 'outro professor',
      turma: t.turma,
    );
  }

  /// Professor da aula em que o PC está preso (trava viva de OUTRO professor),
  /// ou null se o PC está livre para mim.
  String? professorQueTravou(String deviceId) {
    final locks = _aulaLocks;
    if (locks == null || !locks.travadoPorOutro(deviceId)) return null;
    return locks.travaVivaDe(deviceId)?.professor ?? 'outro professor';
  }

  /// Manda um comando (um id por PC) aos PCs alvo e acompanha a entrega na
  /// faixa (envio novo substitui a anterior).
  Future<void> _enviarParaAlvo(Map<String, dynamic> Function() montar) =>
      _enviarComEntrega(_devicesAlvo(), (_) => montar());

  /// Abre uma URL nos PCs alvo (turma, ou só vinculados durante a aula).
  void abrirEmTodos(String url) {
    _enviarParaAlvo(() => buildOpenUrl(url));
  }

  /// Abre uma URL em um PC específico.
  void abrirEm(String deviceId, String url) {
    _enviarComEntrega([deviceId], (_) => buildOpenUrl(url), umPc: true);
  }

  /// Fecha uma aba específica (URL exata) em um PC.
  void fecharAbaEm(String deviceId, String url) {
    _transport?.sendCommand(deviceId, buildCloseTabs(url: url));
  }

  /// Fecha todas as abas de um domínio nos PCs alvo.
  void fecharSiteEmTodos(String domain) {
    _enviarParaAlvo(() => buildCloseTabs(domain: domain));
  }

  /// Fecha todas as abas de um domínio em um PC.
  void fecharSiteEm(String deviceId, String domain) {
    _transport?.sendCommand(deviceId, buildCloseTabs(domain: domain));
  }

  /// Fecha TODAS as abas dos PCs alvo (deixa 1 aba vazia em cada).
  void fecharTodasAsAbasEmTodos() {
    _enviarParaAlvo(buildCloseAllTabs);
  }

  /// Fecha TODAS as abas de um PC (deixa 1 aba vazia).
  void fecharTodasAsAbasEm(String deviceId) {
    _transport?.sendCommand(deviceId, buildCloseAllTabs());
  }

  // ---- Histórico de aulas (Firebase, cifrado; ver history_store.dart) -------------

  /// Aulas em que o aluno aparece, mais recentes primeiro (vazio se o
  /// transporte ainda não subiu).
  Future<List<AulaMeta>> aulasDoAluno(String aluno) async =>
      await _history?.aulasDoAluno(aluno) ?? const [];

  /// Eventos do aluno numa aula, ordenados por hora.
  Future<List<NavEvent>> eventosDoAluno(String sessionId, String aluno) async =>
      await _history?.eventosDoAluno(sessionId, aluno) ?? const [];

  Future<void> apagarAulaDoHistorico(String sessionId) async {
    await _history?.apagarSessao(sessionId);
    notifyListeners();
  }

  Future<void> apagarHistoricoDoAluno(String aluno) async {
    await _history?.apagarAluno(aluno);
    notifyListeners();
  }

  Future<void> apagarTodoHistorico() async {
    await _history?.apagarTudo();
    notifyListeners();
  }

  // ---- Turmas e alunos (só no celular — nunca vão ao Firebase) -------------------

  List<Turma> get turmas => _students?.turmas ?? const [];

  Future<void> adicionarTurma(String nome) async {
    await _students?.adicionarTurma(nome);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  Future<void> renomearTurma(int indice, String nome) async {
    await _students?.renomearTurma(indice, nome);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  Future<void> removerTurma(int indice) async {
    await _students?.removerTurma(indice);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  Future<void> adicionarAluno(int turmaIndice, String aluno) async {
    await _students?.adicionarAluno(turmaIndice, aluno);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  Future<void> renomearAluno(int turmaIndice, int alunoIndice, String nome) async {
    await _students?.renomearAluno(turmaIndice, alunoIndice, nome);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  Future<void> removerAluno(int turmaIndice, int alunoIndice) async {
    await _students?.removerAluno(turmaIndice, alunoIndice);
    _schoolSync?.push('turmas');
    notifyListeners();
  }

  // ---- Sessão de aula --------------------------------------------------------------

  bool get aulaAtiva => _session?.ativa ?? false;

  String get turmaDaAula => _session?.turma ?? '';

  /// Aluno vinculado a um PC nesta aula (null = sem vínculo).
  String? alunoDe(String deviceId) => _session?.alunoDe(deviceId);

  /// Alunos da turma da aula que ainda não estão em nenhum PC.
  List<String> get alunosDisponiveis {
    final s = _session;
    if (s == null || !s.ativa) return const [];
    final turma = _students?.turmaPorNome(s.turma);
    if (turma == null) return const [];
    final usados = s.vinculos.values.toSet();
    return turma.alunos.where((a) => !usados.contains(a)).toList();
  }

  /// Total de alunos da turma da aula (p/ o banner "N/M vinculados").
  int get totalAlunosDaTurma =>
      _students?.turmaPorNome(_session?.turma ?? '')?.alunos.length ?? 0;

  int get totalVinculados => _session?.vinculos.length ?? 0;

  Future<void> iniciarAula(String turma) async {
    await _session?.iniciar(turma);
    final session = _session;
    if (session != null && session.ativa) {
      await _history?.abrirSessao(
        turma,
        session.inicio.millisecondsSinceEpoch,
      );
    }
    notifyListeners();
  }

  /// Vincula aluno↔PC na aula. No workspace, reserva o PC primeiro (1 PC em
  /// 1 aula por vez). Retorna null (ok) ou o motivo da recusa.
  Future<String?> vincularAluno(String deviceId, String aluno) async {
    final locks = _aulaLocks;
    if (locks != null) {
      final erro = await locks.travar(
        deviceId,
        professor: deviceName,
        turma: turmaDaAula,
      );
      if (erro != null) return erro;
    }
    await _session?.vincular(deviceId, aluno);
    // PC que entra na aula depois herda a trava e a prova vigentes.
    unawaited(_herdarEstadoDaTurma(deviceId));
    notifyListeners();
    return null;
  }

  /// Cadastra um aluno na turma da aula (se ainda não existir) e o vincula ao
  /// PC. Retorna null em sucesso ou mensagem de erro (PT-BR).
  Future<String?> cadastrarEVincularAluno(String deviceId, String nome) async {
    final n = nome.trim();
    if (n.isEmpty) return 'Digite o nome do aluno.';
    if (!aulaAtiva) return 'Inicie uma aula primeiro.';
    final students = _students;
    final turmaNome = turmaDaAula;
    final indice =
        students?.turmas.indexWhere((t) => t.nome == turmaNome) ?? -1;
    if (students == null || indice < 0) {
      return 'Turma da aula não encontrada.';
    }
    // adicionarAluno ignora duplicata; se já existe, segue direto p/ o vínculo.
    await students.adicionarAluno(indice, n);
    _schoolSync?.push('turmas');
    return vincularAluno(deviceId, n);
  }

  Future<void> desvincularAluno(String deviceId) async {
    // Saiu da aula: trava e prova daquele PC são desligadas (se ligadas).
    await _desligarEstadoNoPc(deviceId);
    await _aulaLocks?.destravar(deviceId);
    await _session?.desvincular(deviceId);
    notifyListeners();
  }

  /// Encerra a aula, nesta ordem: desliga trava e prova (todo PC com o
  /// estado ligado, mesmo sem aluno) → fecha a grade → fecha o NAVEGADOR com
  /// `fimDeAula` (o PC limpa chat, pedidos e contadores) → apaga o up/ do
  /// alvo → derruba as liberações (o bloqueio integral volta) → solta as
  /// reservas → devolve o telão.
  Future<void> encerrarAula() async {
    // Alvo calculado ANTES de encerrar (encerrar limpa os vínculos).
    final alvo = _devicesAlvo();
    await _desligarTravaEProvaDeTodos();
    await fecharGrade();
    await _enviarComEntrega(
      alvo,
      (_) => buildCloseAllTabs(closeWindows: true, fimDeAula: true),
    );
    await _limparRecadosDe(alvo);
    await _history?.fecharSessao();
    final comExcecao = _session?.devicesComExcecao ?? const <String>[];
    await _session?.encerrar();
    for (final deviceId in comExcecao) {
      if (_travadoPorOutro(deviceId)) continue; // PC já é da aula de outro
      _distribuirRegrasPara(deviceId); // snapshot volta ao completo
    }
    await _aulaLocks?.destravarTodas();
    // Telão é "da aula": encerrar devolve o PC ao papel normal (decisão do
    // usuário — o telão é por conta e morre com a aula).
    marcarPcProfessor(null);
    notifyListeners();
  }

  // ---- Regras -------------------------------------------------------------------

  List<DomainRule> get regras => _rules?.regras ?? const [];

  /// Filtros prontos da escola (Shorts, Reels, TikTok, IAs, canais).
  Filtros get filtros => _rules?.filtros ?? Filtros.padrao;

  Future<void> definirFiltros(Filtros novos) async {
    await _rules?.definirFiltros(novos);
    _schoolSync?.push('rules');
    _distribuirRegras();
  }

  Future<void> adicionarRegra(String pattern, String action) async {
    await _rules?.adicionar(pattern, action);
    _schoolSync?.push('rules');
    _distribuirRegras();
  }

  Future<void> atualizarRegra(int indice, String pattern, String action) async {
    await _rules?.atualizarEm(indice, pattern, action);
    _schoolSync?.push('rules');
    _distribuirRegras();
  }

  Future<void> removerRegra(int indice) async {
    await _rules?.removerEm(indice);
    _schoolSync?.push('rules');
    _distribuirRegras();
  }

  void _distribuirRegras() {
    final transport = _transport;
    if (_rules == null || transport == null) return;
    // Snapshot por PC: liberações da aula variam por device. PCs presos na
    // aula de OUTRO professor ficam de fora — o dono da trava redistribui os
    // dele (com as liberações locais dele) quando o sync entregar a mudança.
    for (final s in transport.registry.all) {
      if (_travadoPorOutro(s.deviceId)) continue;
      _distribuirRegrasPara(s.deviceId);
    }
    notifyListeners();
  }

  // Mudança vinda de outro celular: reenviar a todos derrubaria liberações
  // feitas por outros professores fora de aula.
  void _redistribuirRegrasRemotas() {
    final transport = _transport;
    final locks = _aulaLocks;
    final session = _session;
    if (_rules == null || transport == null) return;
    final todos = transport.registry.all.map((s) => s.deviceId).toList();
    final alvo = alvoDeRegrasRemotas(
      todos: todos,
      meus: {
        for (final id in todos)
          if ((locks?.travadoPorMim(id) ?? false) ||
              (session?.excecoesDe(id).isNotEmpty ?? false))
            id,
      },
      travadosPorOutros:
          locks == null ? const {} : todos.where(locks.travadoPorOutro).toSet(),
    );
    for (final id in alvo) {
      _distribuirRegrasPara(id);
    }
  }

  bool _travadoPorOutro(String deviceId) =>
      _aulaLocks?.travadoPorOutro(deviceId) ?? false;

  /// Grava o set_rules do PC; devolve a escrita (o pedido de liberação
  /// espera por ela para mandar o `rulesRev` certo).
  Future<void> _distribuirRegrasPara(String deviceId, {void Function(int rev)? rev}) {
    final cmd = _setRulesPara(deviceId);
    final r = (cmd['payload'] as Map)['rev'];
    if (r is int) rev?.call(r);
    return _transport?.setStateOne(deviceId, cmd) ?? Future.value();
  }

  // ---- IAs por PC ------------------------------------------------------------------
  // Valem só para a conta aberta agora: o agente desfaz quando a pessoa sai.

  bool iasLiberadasEm(String deviceId) =>
      _transport?.registry.byId(deviceId)?.iasLiberadas ?? false;

  /// null = ok; senão o motivo em linguagem leiga.
  Future<String?> liberarIas(String deviceId, bool liberar) async {
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    final transport = _transport;
    final s = transport?.registry.byId(deviceId);
    if (transport == null || s == null) return 'Ainda conectando — tente de novo.';
    if (liberar && s.usuario == null) return 'Ninguém entrou numa conta neste PC agora.';
    await transport.sendCommand(deviceId, buildLiberarIas(liberar: liberar));
    // Otimista: o próximo relatório do PC confirma (ou desfaz).
    s.iasLiberadas = liberar;
    notifyListeners();
    return null;
  }

  // ---- Liberações por PC ----------------------------------------------------------
  // Valem até o professor bloquear de novo ou até o próximo "Encerrar aula"
  // (decisão do usuário: não exigem aula em andamento).

  /// Padrões de bloqueio liberados para um PC.
  Set<String> liberacoesDe(String deviceId) =>
      _session?.excecoesDe(deviceId) ?? const {};

  /// Padrões de bloqueio cadastrados (candidatos a liberação).
  List<String> get padroesBloqueio => [
        for (final r in regras)
          if (r.action == RuleAction.block) r.pattern,
      ];

  /// Libera um padrão bloqueado para UM PC. Retorna null (ok) ou o motivo da
  /// recusa: PC na aula de outro professor é dele.
  Future<String?> liberarPara(String deviceId, String pattern) async {
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    await _session?.liberar(deviceId, pattern);
    _distribuirRegrasPara(deviceId);
    notifyListeners();
    return null;
  }

  /// Revoga a liberação (o bloqueio volta a valer na hora).
  Future<void> revogarLiberacao(String deviceId, String pattern) async {
    await _session?.revogar(deviceId, pattern);
    if (!_travadoPorOutro(deviceId)) _distribuirRegrasPara(deviceId);
    notifyListeners();
  }

  // ---- Favoritos ------------------------------------------------------------------

  List<Favorito> get favoritos => _favorites?.itens ?? const [];

  Future<void> adicionarFavorito(String label, String url) async {
    await _favorites?.adicionar(label, url);
    notifyListeners();
  }

  Future<void> editarFavorito(int indice, String label, String url) async {
    await _favorites?.editarEm(indice, label, url);
    notifyListeners();
  }

  Future<void> removerFavorito(int indice) async {
    await _favorites?.removerEm(indice);
    notifyListeners();
  }

  Future<void> moverFavorito(int de, int para) async {
    await _favorites?.mover(de, para);
    notifyListeners();
  }

  // ---- Papel de parede -------------------------------------------------------------

  String? get wallpaperHash => _wallpaper?.hash;

  /// Publica o blob no RTDB (compartilhado pela turma) e grava o comando de
  /// estado (só o hash) em cada PC. Vale no ChromeOS e no Celita OS.
  Future<void> definirPapelDeParede(Uint8List bytes) async {
    final transport = _transport;
    if (transport == null) return;
    if (bytes.length > 4 * 1024 * 1024) {
      throw ArgumentError('imagem_grande'); // vira base64 ~5.3MB no banco
    }
    final hash = c.sha256.convert(bytes).toString().substring(0, 8);
    await transport.publishWallpaper(bytes, hash);
    await _wallpaper?.definir(hash);
    await transport.setStateAll(buildSetWallpaper(hash));
    notifyListeners();
  }

  // ---- Página inicial dos alunos ---------------------------------------------------

  PaginaInicial get paginaInicial => _home?.config ?? PaginaInicial.padrao;

  /// Motivo de a última publicação não ter ido ao ar, em português, ou null.
  String? get erroPaginaInicial => _erroPaginaInicial;

  Future<void> definirTituloDaPagina(String titulo) async {
    await _home?.definirTitulo(titulo);
    await _publicarPaginaInicial();
  }

  /// Site aberto no lugar da página; false = endereço recusado.
  Future<bool> definirUrlDaPagina(String url) async {
    final aceito = await _home?.definirUrl(url) ?? false;
    if (aceito) await _publicarPaginaInicial();
    return aceito;
  }

  Future<void> definirBuscaDaPagina(bool ligada) async {
    await _home?.definirBusca(ligada);
    await _publicarPaginaInicial();
  }

  Future<void> definirBuscadorDaPagina(String buscador) async {
    await _home?.definirBuscador(buscador);
    await _publicarPaginaInicial();
  }

  Future<bool> adicionarAtalhoDaPagina(String label, String url) async {
    final aceito = await _home?.adicionar(label, url) ?? false;
    if (aceito) await _publicarPaginaInicial();
    return aceito;
  }

  Future<bool> editarAtalhoDaPagina(int indice, String label, String url) async {
    final aceito = await _home?.editarEm(indice, label, url) ?? false;
    if (aceito) await _publicarPaginaInicial();
    return aceito;
  }

  Future<void> removerAtalhoDaPagina(int indice) async {
    await _home?.removerEm(indice);
    await _publicarPaginaInicial();
  }

  Future<void> moverAtalhoDaPagina(int de, int para) async {
    await _home?.mover(de, para);
    await _publicarPaginaInicial();
  }

  /// Republica o que já está salvo. Serve para o botão "tentar de novo" depois
  /// de o professor entrar com o Google ou a internet voltar.
  Future<void> republicarPaginaInicial() => _publicarPaginaInicial();

  // A escrita é da escola inteira e as regras exigem conta Google. Guardar o
  // motivo em vez de estourar deixa a tela dizer o que fazer.
  Future<void> _publicarPaginaInicial() async {
    final home = _home;
    final transport = _transport;
    if (home == null) return;
    if (transport == null) {
      _erroPaginaInicial = 'Sem conexão com o servidor. Tente de novo.';
      notifyListeners();
      return;
    }
    if (!logadoComGoogle) {
      _erroPaginaInicial = 'Entre com o Google (em Ajustes) para publicar a página.';
      notifyListeners();
      return;
    }
    try {
      await transport.publicarPaginaInicial(home.config.toMap());
      _erroPaginaInicial = null;
    } catch (e) {
      _erroPaginaInicial = 'Não foi possível publicar agora. Tente de novo.';
      debugPrint('publicarPaginaInicial: $e');
    }
    notifyListeners();
  }

  // ==== Recursos de turma (SPEC-turma) =========================================
  // Chat (29), Recados com pedidos de liberação e mão levantada (27),
  // confirmação de entrega (26), "Olhos em mim" (24), modo prova (25) e a
  // grade de miniaturas (23). O alvo de tudo que é "da turma" é
  // [pcsDaTurma]: só com aula ativa, só PCs da aula (na escola, reservados
  // por mim).

  // ---- Alvo e nomes ---------------------------------------------------------------

  List<String> _alvoTurma() {
    final registry = _transport?.registry;
    final locks = _aulaLocks;
    final ids = (registry?.all ?? const <PcSession>[]).map((s) => s.deviceId).toList();
    return alvoDeTurma(
      aulaAtiva: aulaAtiva,
      vinculados: (_session?.vinculos.keys ?? const <String>[])
          .where((id) => registry?.byId(id) != null),
      pcProfessorId: _pcProfessorId,
      modoEscola: workspaceAtivo,
      reservadosPorMim:
          locks == null ? const {} : ids.where(locks.travadoPorMim).toSet(),
      reservadosPorOutros:
          locks == null ? const {} : ids.where(locks.travadoPorOutro).toSet(),
    );
  }

  /// PCs da turma agora (alvo de trava, prova, grade e "Mensagem para a
  /// turma"): vazio sem aula ativa.
  List<String> get pcsDaTurma => _alvoTurma();

  /// Texto quando um recurso de turma não tem alvo (null = tem).
  String? get motivoSemTurma {
    if (!aulaAtiva) return 'Comece uma aula para usar com a turma.';
    if (_alvoTurma().isEmpty) return 'Nenhum computador com aluno nesta aula ainda.';
    return null;
  }

  /// Nome do aluno vinculado ou, sem vínculo, o nome do PC.
  String nomeDoPc(String deviceId) {
    final aluno = alunoDe(deviceId);
    if (aluno != null) return aluno;
    final s = pcPorId(deviceId);
    return s != null ? nomeDe(s) : 'Computador';
  }

  /// PCs que aparecem em Recados: todos, menos os da aula de outro professor.
  Iterable<PcSession> get _pcsDosRecados => pcs.where((s) => !_travadoPorOutro(s.deviceId));

  // ---- Escritas novas (falha macia: SPEC-turma §1.3) ------------------------------

  /// Grava estados (state/lock|exam|monitor) e devolve null ou o texto ao
  /// professor. Sem conexão não espera a fila do SDK; negado pelas rules vira
  /// "O servidor da escola ainda não foi atualizado…" — nunca sucesso falso.
  Future<String?> _gravarEstados(Map<String, Map<String, dynamic>> porPc) async {
    final t = _transport;
    if (t == null) return 'Ainda conectando — tente de novo.';
    if (porPc.isEmpty) return null;
    if (!t.conectado) return kTextoSemInternet;
    try {
      await Future.wait([
        for (final e in porPc.entries) t.setStateOne(e.key, e.value),
      ]).timeout(const Duration(seconds: 15));
      return null;
    } on FirebaseException catch (e) {
      debugPrint('[CdA] estado de turma recusado: ${e.code} ${e.message}');
      return textoErroDeEscrita(e.code);
    } catch (e) {
      debugPrint('[CdA] estado de turma falhou: $e');
      return kTextoSemInternet;
    }
  }

  // ---- Entrega (faixa) -------------------------------------------------------------

  Entrega? _entrega;
  String? _entregaUmPc; // deviceId quando o envio foi para UM PC
  Timer? _entregaTimer;
  Entrega? _entregaTrava;
  Timer? _entregaTravaTimer;
  Entrega? _entregaProva;
  Timer? _entregaProvaTimer;

  /// Último envio de turma (ou para um PC). Envio novo substitui o anterior.
  Entrega? get entrega => _entrega;

  /// Texto da faixa do último envio ("Enviando… 3 de 20", "✓ Todos
  /// receberam (20)", "Ana recebeu ✓"…), ou null.
  String? get textoDaEntrega {
    final e = _entrega;
    if (e == null) return null;
    final umPc = _entregaUmPc;
    if (umPc != null) {
      return textoEntregaUmPc(e, nomeDoPc(umPc), ext: pcPorId(umPc)?.versaoExt);
    }
    return textoEntrega(e);
  }

  /// Confirmação da última mudança de "Olhos em mim".
  Entrega? get entregaTrava => _entregaTrava;
  String? get textoDaTrava {
    final e = _entregaTrava;
    if (e == null) return null;
    final desde = _session?.trava.desde ?? 0;
    return textoTrava(
      e,
      desde: e.alvoOn && desde > 0 ? DateTime.fromMillisecondsSinceEpoch(desde) : null,
    );
  }

  /// Confirmação da última mudança do modo prova.
  Entrega? get entregaProva => _entregaProva;
  String? get textoDaProva => _entregaProva == null ? null : textoProva(_entregaProva!);

  /// Linha por PC do detalhe ("Unidade 3 · Ana — Recebeu ✓").
  String textoDaEntregaNoPc(Entrega e, EntregaPc p) {
    final numero = numeroDe(p.deviceId);
    final nome = nomeDoPc(p.deviceId);
    final prefixo = numero != null && alunoDe(p.deviceId) != null ? 'Unidade $numero · ' : '';
    return '$prefixo$nome — ${textoDoPc(e, p, ext: pcPorId(p.deviceId)?.versaoExt)}';
  }

  /// Esconde a faixa do último envio (o professor dispensou).
  void dispensarEntrega() {
    _entrega = null;
    _entregaUmPc = null;
    _entregaTimer?.cancel();
    notifyListeners();
  }

  Timer _timerDeEntrega(Entrega e) => Timer(
        e.timeout + const Duration(milliseconds: 200),
        () {
          e.aoTempo(DateTime.now());
          notifyListeners();
        },
      );

  void _novaEntrega(Entrega e, {String? umPc}) {
    _entrega = e;
    _entregaUmPc = umPc;
    _entregaTimer?.cancel();
    _entregaTimer = _timerDeEntrega(e);
  }

  void _novaEntregaDeEstado(Entrega e) {
    if (e.tipo == TipoEntrega.trava) {
      _entregaTrava = e;
      _entregaTravaTimer?.cancel();
      _entregaTravaTimer = _timerDeEntrega(e);
    } else {
      _entregaProva = e;
      _entregaProvaTimer?.cancel();
      _entregaProvaTimer = _timerDeEntrega(e);
    }
  }

  /// Comando one-shot para [alvos] (um id por PC), acompanhado na faixa.
  Future<void> _enviarComEntrega(
    List<String> alvos,
    Map<String, dynamic> Function(String deviceId) montar, {
    bool umPc = false,
  }) async {
    final transport = _transport;
    if (transport == null || alvos.isEmpty) return;
    final e = Entrega(tipo: TipoEntrega.comando, enviadoEm: DateTime.now());
    final envios = <String, Map<String, dynamic>>{};
    for (final id in alvos) {
      final s = transport.registry.byId(id);
      if (s == null) continue;
      final cmd = montar(id);
      envios[id] = cmd;
      e.adicionar(
        id,
        cmdId: cmd['id'] as String?,
        online: isOnline(s),
        suportaTurma: suportaTurma(s.versaoExt),
      );
    }
    _novaEntrega(e, umPc: umPc && envios.length == 1 ? envios.keys.first : null);
    notifyListeners();
    // Sem rede o SDK guarda as escritas (na ordem) e manda ao reconectar: não
    // prende quem chamou (nem além de 15 s com rede lenta).
    final escritas = Future.wait([
      for (final x in envios.entries)
        transport.sendCommand(x.key, x.value).catchError((Object err) {
          debugPrint('[CdA] envio para ${x.key} falhou: $err');
          return null;
        }),
    ]);
    if (!transport.conectado) return;
    await escritas.timeout(const Duration(seconds: 15), onTimeout: () => const []);
  }

  // Ack e `aplicado`: corrigem a faixa e os balões (ack tardio sempre corrige).
  void _aoAck(String deviceId, Ack ack) {
    var mudou = _entrega?.aoAck(deviceId, ack.id, ok: ack.ok, error: ack.error) ?? false;
    mudou = _atualizarBalao(deviceId, ack.id, ack.ok, ack.error) || mudou;
    if (mudou) _scheduleNotify();
  }

  void _aoAplicado(String deviceId, Aplicado aplicado) {
    var mudou = false;
    for (final e in [_entrega, _entregaTrava, _entregaProva]) {
      if (e != null && e.aoAplicado(deviceId, aplicado)) mudou = true;
    }
    for (final a in aplicado.acks) {
      if (_atualizarBalao(deviceId, a.id, a.ok, a.error)) mudou = true;
    }
    if (mudou) _scheduleNotify();
  }

  // ---- Conversas (chat) -------------------------------------------------------------

  final List<Timer> _semRespostaTimers = [];

  /// Conversa com o aluno do PC, em ordem de hora.
  List<ChatItem> conversaDe(String deviceId) =>
      List.unmodifiable(pcPorId(deviceId)?.chat ?? const <ChatItem>[]);

  int naoLidasDe(String deviceId) => pcPorId(deviceId)?.naoLidas ?? 0;

  /// Abrir a conversa zera as não lidas e baixa a mão (apaga o up/).
  Future<void> abrirConversa(String deviceId) async {
    final s = pcPorId(deviceId);
    if (s == null) return;
    s.naoLidas = 0;
    notifyListeners();
    if (s.maoMids.isNotEmpty || s.maoEm != null) await baixarMao(deviceId);
  }

  /// Só zera as não lidas (conversa aberta na tela enquanto chega mensagem).
  void marcarConversaLida(String deviceId) {
    final s = pcPorId(deviceId);
    if (s == null || s.naoLidas == 0) return;
    s.naoLidas = 0;
    notifyListeners();
  }

  /// Valida o texto do professor; null = ok.
  String? _validarTextoChat(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return 'Escreva a mensagem.';
    if (contarCodePoints(t) > kMaxChatTexto) {
      return 'Mensagem muito longa (máx. $kMaxChatTexto letras).';
    }
    return null;
  }

  /// "Conversar": manda [texto] ao aluno do PC. PC antigo recebe a mensagem
  /// como aviso (show_message) e o balão diz que ele não consegue responder.
  /// null = enviada (o balão mostra a entrega).
  Future<String?> enviarChat(String deviceId, String texto) async {
    final erro = _validarTextoChat(texto);
    if (erro != null) return erro;
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    final r = await _enviarChatPara(deviceId, texto.trim(), paraTurma: false);
    return r;
  }

  /// "Mensagem para a turma": um chat_message para cada PC da turma (cada
  /// aluno responde na própria conversa). A faixa acompanha a entrega.
  Future<String?> enviarMensagemParaTurma(String texto) async {
    final erro = _validarTextoChat(texto);
    if (erro != null) return erro;
    final sem = motivoSemTurma;
    if (sem != null) return sem;
    if (!(_transport?.conectado ?? false)) return kTextoSemInternet;
    final e = Entrega(
      tipo: TipoEntrega.comando,
      enviadoEm: DateTime.now(),
      tipoComando: MessageType.chatMessage,
    );
    _novaEntrega(e);
    await Future.wait([
      for (final id in _alvoTurma())
        _enviarChatPara(id, texto.trim(), paraTurma: true, entrega: e),
    ]);
    return null;
  }

  Future<String?> _enviarChatPara(
    String deviceId,
    String texto, {
    required bool paraTurma,
    Entrega? entrega,
  }) async {
    final transport = _transport;
    final s = transport?.registry.byId(deviceId);
    if (transport == null || s == null) return 'Ainda conectando — tente de novo.';
    // Sem rede a escrita ficaria presa na fila do SDK e o balão mentiria.
    if (!transport.conectado) return kTextoSemInternet;
    final antigo = !suportaTurma(s.versaoExt);
    final mid = novoId();
    final cmd = antigo
        ? buildShowMessage('Mensagem do professor', texto, popup: true, de: deviceName)
        : buildChatMessage(texto: texto, de: deviceName, mid: mid);
    final cmdId = cmd['id'] as String;
    final online = isOnline(s);
    final item = ChatItem(
      id: mid,
      autor: AutorChat.professor,
      texto: texto,
      ts: agoraServidorMs(),
      cmdId: cmdId,
      estado: online ? EstadoBalao.enviando : EstadoBalao.aguardando,
      paraTurma: paraTurma,
      versaoAntiga: antigo,
    );
    _anexarChat(s, item);
    // O aviso para PC antigo é comando que ele entende: entra na contagem
    // normal (o balão já diz que o aluno não responde).
    entrega?.adicionar(deviceId, cmdId: cmdId, online: online, suportaTurma: true);
    if (online) {
      _semRespostaTimers.add(
        Timer(kEntregaTimeout, () {
          if (item.estado == EstadoBalao.enviando) {
            item.estado = EstadoBalao.semResposta;
            notifyListeners();
          }
        }),
      );
      _semRespostaTimers.removeWhere((t) => !t.isActive);
    }
    notifyListeners();
    try {
      await transport.sendCommand(deviceId, cmd);
      return null;
    } catch (e) {
      debugPrint('[CdA] chat para $deviceId falhou: $e');
      item.estado = EstadoBalao.erro;
      item.codigoErro = kErroEnvioLocal;
      notifyListeners();
      return kTextoSemInternet;
    }
  }

  /// Ack (ou `aplicado.acks`) de um comando de chat: atualiza o balão.
  bool _atualizarBalao(String deviceId, String cmdId, bool ok, String? error) {
    final s = pcPorId(deviceId);
    if (s == null) return false;
    for (final item in s.chat.reversed) {
      if (item.cmdId != cmdId) continue;
      final EstadoBalao novo;
      String? codigo;
      if (ok) {
        novo = EstadoBalao.entregue;
      } else if (error == 'sem_sessao') {
        novo = EstadoBalao.ninguemLogado;
      } else {
        novo = EstadoBalao.erro;
        codigo = error ?? 'executor_falhou';
      }
      if (item.estado == novo && item.codigoErro == codigo) return false;
      item.estado = novo;
      item.codigoErro = codigo;
      return true;
    }
    return false;
  }

  void _anexarChat(PcSession s, ChatItem item) {
    if (item.autor == AutorChat.aluno &&
        s.chat.any((c) => c.autor == AutorChat.aluno && c.id == item.id)) {
      return;
    }
    var i = s.chat.length;
    while (i > 0 && s.chat[i - 1].ts > item.ts) {
      i--;
    }
    s.chat.insert(i, item);
    if (s.chat.length > kChatHistoricoThread) {
      s.chat.removeRange(0, s.chat.length - kChatHistoricoThread);
    }
  }

  // ---- up/ (aluno -> professor) ----------------------------------------------------

  int _upInicioMs = 0;
  final Map<String, int> _silenciadosAte = {};

  DestinoUp _destinoDoUp(String deviceId) {
    final locks = _aulaLocks;
    if (workspaceAtivo && (locks == null || !locks.carregado)) {
      // Ainda não se sabe de quem é o PC: espera (nem lê, nem apaga).
      return DestinoUp.ignorar;
    }
    return destinoDoUp(
      modoEscola: workspaceAtivo,
      reservadoPorOutro: locks?.travadoPorOutro(deviceId) ?? false,
      reservadoPorMim: locks?.travadoPorMim(deviceId) ?? false,
    );
  }

  bool _maoVisivel(PcSession s, int agoraMs) {
    final em = s.maoEm;
    return em != null && agoraMs - em < kMaoVisivel.inMilliseconds;
  }

  void _aoUp(String deviceId, UpMessage msg, int ms, DestinoUp destino) {
    final s = pcPorId(deviceId);
    if (s == null) return;
    final nome = nomeDoPc(deviceId);
    final notifs = notificacoes;
    // Só toca o celular para o que chegou ao vivo, e só para quem é dono.
    final notificar = notifs != null &&
        destino == DestinoUp.mostrarENotificar &&
        ms >= _upInicioMs;
    switch (msg.type) {
      case UpType.chat:
        if (s.chat.any((c) => c.autor == AutorChat.aluno && c.id == msg.mid)) break;
        _anexarChat(
          s,
          ChatItem(id: msg.mid, autor: AutorChat.aluno, texto: msg.texto!, ts: ms),
        );
        s.naoLidas++;
        if (notificar) {
          unawaited(notifs.notificarRecado(
            k: 'chat',
            deviceId: deviceId,
            ts: ms,
            titulo: nome,
            corpo: msg.texto!,
          ),);
        }
      case UpType.unblockRequest:
        PedidoLiberacao? existente;
        for (final p in s.pedidos) {
          if (p.site == msg.site) existente = p;
        }
        if (existente != null) {
          existente.juntar(
            mid: msg.mid,
            url: msg.url ?? '',
            motivo: msg.motivo ?? '',
            bloqueio: msg.bloqueio ?? 'regra',
            ts: ms,
          );
        } else {
          s.pedidos.add(
            PedidoLiberacao(
              deviceId: deviceId,
              mid: msg.mid,
              site: msg.site!,
              url: msg.url ?? '',
              motivo: msg.motivo ?? '',
              bloqueio: msg.bloqueio ?? 'regra',
              ts: ms,
            ),
          );
        }
        if (notificar) {
          unawaited(notifs.notificarRecado(
            k: 'pedido',
            deviceId: deviceId,
            ts: ms,
            titulo: 'Pedido de liberação',
            corpo: '$nome: ${msg.site}',
          ),);
        }
      case UpType.raiseHand:
        final jaLevantada = _maoVisivel(s, agoraServidorMs());
        s.maoMids.add(msg.mid);
        if (s.maoEm == null || ms > s.maoEm!) s.maoEm = ms;
        // Notifica só na transição para levantada.
        if (notificar && !jaLevantada && _maoVisivel(s, agoraServidorMs())) {
          unawaited(notifs.notificarRecado(
            k: 'mao',
            deviceId: deviceId,
            ts: ms,
            titulo: 'Mão levantada',
            corpo: nome,
          ),);
        }
    }
    _scheduleNotify();
  }

  void _aoUpRemovido(String deviceId, String mid) {
    final s = pcPorId(deviceId);
    if (s == null) return;
    // Outro aparelho resolveu (ou o PC podou): sai de Recados. Chat fica na
    // conversa (a poda do PC não apaga o que o professor já viu).
    for (final p in s.pedidos.toList()) {
      if (p.mids.remove(mid) && p.mids.isEmpty) s.pedidos.remove(p);
    }
    if (s.maoMids.remove(mid) && s.maoMids.isEmpty) s.maoEm = null;
    _scheduleNotify();
  }

  void _aoUpSilenciado(String deviceId) {
    _silenciadosAte[deviceId] =
        agoraServidorMs() + const Duration(minutes: 10).inMilliseconds;
    _scheduleNotify();
  }

  // ---- Recados ---------------------------------------------------------------------

  /// Pedidos de liberação pendentes, do mais antigo para o mais novo.
  List<PedidoLiberacao> get pedidosPendentes {
    final l = [for (final s in _pcsDosRecados) ...s.pedidos]
      ..sort((a, b) => a.ts.compareTo(b.ts));
    return l;
  }

  /// PCs com a mão levantada há menos de 10 min (some sozinha da tela).
  List<PcSession> get maosLevantadas {
    final agora = agoraServidorMs();
    return _pcsDosRecados.where((s) => _maoVisivel(s, agora)).toList()
      ..sort((a, b) => a.maoEm!.compareTo(b.maoEm!));
  }

  /// PCs com conversa, a mais recente primeiro.
  List<PcSession> get conversas {
    final l = _pcsDosRecados.where((s) => s.chat.isNotEmpty).toList()
      ..sort((a, b) => b.chat.last.ts.compareTo(a.chat.last.ts));
    return l;
  }

  /// PCs silenciados agora por excesso de mensagens (linha em Recados).
  List<String> get pcsSilenciados {
    final agora = agoraServidorMs();
    return [
      for (final e in _silenciadosAte.entries)
        if (e.value > agora && !_travadoPorOutro(e.key)) e.key,
    ];
  }

  /// Badge do ícone Recados: pedidos + mãos + conversas com não lidas.
  int get recadosCount =>
      pedidosPendentes.length +
      maosLevantadas.length +
      conversas.where((s) => s.naoLidas > 0).length;

  /// Regras que "Liberar" tiraria deste PC (fora da prova). Mais de uma =
  /// confirmar "Liberar para {nome}: {p1}, {p2}?".
  List<String> padroesParaLiberar(PedidoLiberacao pedido) {
    final jaLiberados = liberacoesDe(pedido.deviceId);
    return padroesQueCasam(regras, urlParaCasar(pedido.url, pedido.site))
        .where((p) => !jaLiberados.contains(p))
        .toList();
  }

  /// O PC está em prova agora (estado gravado e dentro do prazo)?
  bool provaNoPc(String deviceId) =>
      pcPorId(deviceId)?.prova?.vigente(agoraServidorMs()) ?? false;

  /// "Liberar": fora da prova tira as regras que casam a URL pedida (cada
  /// uma vira liberação deste PC); em prova acrescenta o site ao `allow`
  /// deste PC. Depois responde ao aluno e apaga o pedido. null = ok.
  Future<String?> liberarPedido(PedidoLiberacao pedido, {List<String>? padroes}) async {
    final deviceId = pedido.deviceId;
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) return 'Ainda conectando — tente de novo.';
    if (!transport.conectado) return kTextoSemInternet;
    int? rulesRev;
    int? examRev;
    if (provaNoPc(deviceId)) {
      final novo = await session.liberarNaProva(deviceId, pedido.site);
      final rev = _proximoRev();
      final erro = await _gravarEstados({deviceId: _setExamPara(deviceId, on: true, rev: rev)});
      if (erro != null) {
        // O professor viu o erro: o site não pode ser liberado depois, calado,
        // pela renovação de 5 min. O pedido continua em Recados.
        if (novo) await session.revogarNaProva(deviceId, pedido.site);
        return erro;
      }
      examRev = rev;
    } else {
      final lista = padroes ?? padroesParaLiberar(pedido);
      if (lista.isNotEmpty) {
        for (final p in lista) {
          await session.liberar(deviceId, p);
        }
        try {
          await _distribuirRegrasPara(deviceId, rev: (r) => rulesRev = r)
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('[CdA] liberar pedido: $e');
          return kTextoSemInternet;
        }
      }
    }
    final erro = await _responderPedido(
      deviceId,
      buildUnblockResult(
        mid: pedido.mid,
        site: pedido.site,
        approved: true,
        rulesRev: rulesRev,
        examRev: examRev,
      ),
    );
    if (erro != null) return erro;
    await _resolverPedido(pedido);
    return null;
  }

  /// Manda o unblock_result. Falha vira texto (nunca exceção na tela); o
  /// pedido só sai de Recados se a resposta foi gravada.
  Future<String?> _responderPedido(String deviceId, Map<String, dynamic> cmd) async {
    try {
      await _transport!.sendCommand(deviceId, cmd).timeout(const Duration(seconds: 15));
      return null;
    } on FirebaseException catch (e) {
      debugPrint('[CdA] resposta do pedido recusada: ${e.code} ${e.message}');
      return textoErroDeEscrita(e.code);
    } catch (e) {
      debugPrint('[CdA] resposta do pedido falhou: $e');
      return kTextoSemInternet;
    }
  }

  /// "Recusar": responde ao aluno (com o motivo, se houver) e apaga o pedido.
  Future<String?> recusarPedido(PedidoLiberacao pedido, {String? motivo}) async {
    final deviceId = pedido.deviceId;
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    final transport = _transport;
    if (transport == null) return 'Ainda conectando — tente de novo.';
    if (!transport.conectado) return kTextoSemInternet;
    final erro = await _responderPedido(
      deviceId,
      buildUnblockResult(
        mid: pedido.mid,
        site: pedido.site,
        approved: false,
        motivo: motivo,
      ),
    );
    if (erro != null) return erro;
    await _resolverPedido(pedido);
    return null;
  }

  Future<void> _resolverPedido(PedidoLiberacao pedido) async {
    final s = pcPorId(pedido.deviceId);
    s?.pedidos.remove(pedido);
    notifyListeners();
    for (final mid in pedido.mids) {
      await _transport
          ?.apagarUpDoMid(pedido.deviceId, mid)
          .catchError((Object e) => debugPrint('[CdA] apagar pedido: $e'));
    }
  }

  /// "Baixar" a mão (ou abrir a conversa): apaga o raise_hand do up/.
  Future<void> baixarMao(String deviceId) async {
    final s = pcPorId(deviceId);
    // PC na aula de outro professor: o up/ dele não é meu para apagar.
    if (s == null || _travadoPorOutro(deviceId)) return;
    final mids = s.maoMids.toList();
    s.maoMids.clear();
    s.maoEm = null;
    notifyListeners();
    for (final mid in mids) {
      await _transport
          ?.apagarUpDoMid(deviceId, mid)
          .catchError((Object e) => debugPrint('[CdA] baixar mão: $e'));
    }
  }

  /// Fim de aula: esquece conversa e recados dos PCs do alvo e apaga o up/
  /// deles (sem rede, o PC poda sozinho em 2 h).
  Future<void> _limparRecadosDe(List<String> alvo) async {
    final transport = _transport;
    for (final id in alvo) {
      final s = pcPorId(id);
      if (s != null) {
        s.chat.clear();
        s.naoLidas = 0;
        s.pedidos.clear();
        s.maoMids.clear();
        s.maoEm = null;
      }
      _silenciadosAte.remove(id);
    }
    notifyListeners();
    if (transport == null || !transport.conectado) return;
    await Future.wait([
      for (final id in alvo)
        transport.apagarTodoUp(id).catchError((Object e) {
          debugPrint('[CdA] apagar up de $id: $e');
        }),
    ]).timeout(const Duration(seconds: 15), onTimeout: () => const []);
  }

  // ---- "Olhos em mim" (trava) ------------------------------------------------------

  /// O PC está com a tela travada (state/lock decifrado ligado e no prazo)?
  bool telaTravada(String deviceId) =>
      pcPorId(deviceId)?.trava?.vigente(agoraServidorMs()) ?? false;

  /// Tela travada sem professor com reserva viva (só na escola): qualquer
  /// MEMBRO pode destravar ("Travada sem professor · Destravar").
  bool travadaSemProfessor(String deviceId) =>
      workspaceAtivo &&
      telaTravada(deviceId) &&
      (_aulaLocks?.carregado ?? false) &&
      _aulaLocks?.travaVivaDe(deviceId) == null;

  /// "Olhos em mim" ligado (botão vira "Destravar").
  bool get travaLigada =>
      (_session?.trava.on ?? false) || _alvoTurma().any(telaTravada);

  /// Quando a trava foi ligada (faixa "desde 10:42").
  DateTime? get travaDesde {
    final d = _session?.trava.desde ?? 0;
    return d > 0 ? DateTime.fromMillisecondsSinceEpoch(d) : null;
  }

  Map<String, dynamic> _setLockLigado({int? rev}) {
    final t = _session?.trava ?? TravaDaAula.desligada;
    return buildSetLock(
      rev: rev ?? _proximoRev(),
      on: true,
      texto: t.texto,
      mute: t.mute,
      ate: agoraServidorMs() + kTravaAte.inMilliseconds,
    );
  }

  Map<String, dynamic> _setLockDesligado(String deviceId, int rev) {
    final atual = pcPorId(deviceId)?.trava;
    return buildSetLock(
      rev: rev,
      on: false,
      texto: atual?.texto ?? kTravaTextoPadrao,
      mute: false,
      ate: agoraServidorMs(),
    );
  }

  /// Trava as telas da turma (ou só [apenas], "Escolher computadores").
  /// null = gravado (a faixa confirma PC a PC pelo relatório).
  Future<String?> travarTurma({
    required String texto,
    bool mute = true,
    Iterable<String>? apenas,
  }) async {
    final sem = motivoSemTurma;
    if (sem != null) return sem;
    final escolhidos = apenas?.toSet();
    final alvos = _alvoTurma().where((id) => escolhidos == null || escolhidos.contains(id)).toList();
    if (alvos.isEmpty) return 'Escolha pelo menos um computador.';
    final t = cortarCodePoints(texto.trim(), kMaxTravaTexto);
    final textoFinal = t.isEmpty ? kTravaTextoPadrao : t;
    final rev = _proximoRev();
    final ate = agoraServidorMs() + kTravaAte.inMilliseconds;
    final cmds = {
      for (final id in alvos)
        id: buildSetLock(rev: rev, on: true, texto: textoFinal, mute: mute, ate: ate),
    };
    final erro = await _gravarEstados(cmds);
    if (erro != null) return erro;
    final e = Entrega(
      tipo: TipoEntrega.trava,
      enviadoEm: DateTime.now(),
      alvoOn: true,
      revEnviado: rev,
    );
    for (final id in alvos) {
      final s = pcPorId(id);
      if (s == null) continue;
      e.adicionar(id, online: isOnline(s), suportaTurma: suportaTurma(s.versaoExt), comandoNovo: true);
    }
    _novaEntregaDeEstado(e);
    final desde = (_session?.trava.on ?? false) && (_session?.trava.desde ?? 0) > 0
        ? _session!.trava.desde
        : DateTime.now().millisecondsSinceEpoch;
    await _session?.definirTrava(
      TravaDaAula(on: true, rev: rev, texto: textoFinal, mute: mute, desde: desde),
    );
    notifyListeners();
    return null;
  }

  /// "Destravar": `on:false` a todo PC com a tela travada (menos os da aula
  /// de outro professor), com ou sem aluno.
  Future<String?> destravarTurma() async {
    final alvos = [
      for (final s in pcs)
        if ((s.trava?.on ?? false) && !_travadoPorOutro(s.deviceId)) s.deviceId,
    ];
    return _destravar(alvos);
  }

  /// Destrava um PC só (inclusive "Travada sem professor").
  Future<String?> destravarPc(String deviceId) async {
    final professor = professorQueTravou(deviceId);
    if (professor != null) return 'Está na aula de $professor.';
    return _destravar([deviceId], soEste: true);
  }

  Future<String?> _destravar(List<String> alvos, {bool soEste = false}) async {
    if (alvos.isEmpty) {
      if (!soEste) await _session?.definirTrava(TravaDaAula.desligada);
      notifyListeners();
      return null;
    }
    final rev = _proximoRev();
    final erro = await _gravarEstados({for (final id in alvos) id: _setLockDesligado(id, rev)});
    if (erro != null) return erro;
    final e = Entrega(
      tipo: TipoEntrega.trava,
      enviadoEm: DateTime.now(),
      alvoOn: false,
      revEnviado: rev,
    );
    for (final id in alvos) {
      final s = pcPorId(id);
      if (s == null) continue;
      e.adicionar(id, online: isOnline(s), suportaTurma: suportaTurma(s.versaoExt), comandoNovo: true);
    }
    _novaEntregaDeEstado(e);
    if (!soEste || !_alvoTurma().any((id) => id != alvos.first && telaTravada(id))) {
      await _session?.definirTrava(TravaDaAula.desligada);
    }
    notifyListeners();
    return null;
  }

  // ---- Modo prova ------------------------------------------------------------------

  /// Sites permitidos na prova (lista da escola, store `prova`).
  List<String> get sitesProva => _provaStore?.padroes ?? const [];

  Future<bool> adicionarSiteProva(String pattern) async {
    final ok = await _provaStore?.adicionar(pattern) ?? false;
    if (ok) await _depoisDeEditarProva();
    return ok;
  }

  Future<int> adicionarSitesProvaEmLote(String texto) async {
    final n = await _provaStore?.adicionarEmLote(texto) ?? 0;
    if (n > 0) await _depoisDeEditarProva();
    return n;
  }

  Future<void> removerSiteProva(int indice) async {
    await _provaStore?.removerEm(indice);
    await _depoisDeEditarProva();
  }

  Future<void> _depoisDeEditarProva() async {
    _schoolSync?.push('prova');
    // Editar com a prova ligada redistribui state/exam aos PCs da prova.
    await _redistribuirProva();
    notifyListeners();
  }

  /// Modo prova ligado (botão "Prova ligada").
  bool get provaLigada => (_session?.prova.on ?? false) || _alvoTurma().any(provaNoPc);

  /// PCs da turma que não entrariam em modo prova (versão antiga): o
  /// professor vê o aviso antes de ligar (§8.4).
  List<PcSession> get pcsSemModoProva => [
        for (final id in _alvoTurma())
          if (pcPorId(id) case final s? when !suportaTurma(s.versaoExt)) s,
      ];

  Map<String, dynamic> _setExamPara(String deviceId, {required bool on, required int rev}) {
    final allow = <String>[
      ...sitesProva,
      ...(_session?.provaLiberacoesDe(deviceId) ?? const <String>{}),
    ];
    final inicio = _home?.config.url ?? '';
    return buildSetExam(
      rev: rev,
      on: on,
      allow: allow,
      inicio: inicio.isEmpty ? null : inicio,
      ate: agoraServidorMs() + kProvaAte.inMilliseconds,
    );
  }

  /// Liga o modo prova na turma toda (1 toque). null = gravado.
  Future<String?> ligarProva() async {
    final sem = motivoSemTurma;
    if (sem != null) return sem;
    final alvos = _alvoTurma();
    final rev = _proximoRev();
    final erro = await _gravarEstados({
      for (final id in alvos) id: _setExamPara(id, on: true, rev: rev),
    });
    if (erro != null) return erro;
    final e = Entrega(
      tipo: TipoEntrega.prova,
      enviadoEm: DateTime.now(),
      alvoOn: true,
      revEnviado: rev,
    );
    for (final id in alvos) {
      final s = pcPorId(id);
      if (s == null) continue;
      e.adicionar(id, online: isOnline(s), suportaTurma: suportaTurma(s.versaoExt), comandoNovo: true);
    }
    _novaEntregaDeEstado(e);
    await _session?.definirProva(ProvaDaAula(on: true, rev: rev));
    notifyListeners();
    return null;
  }

  /// Desliga o modo prova (todo PC com a prova ligada, menos os da aula de
  /// outro professor). null = gravado.
  Future<String?> desligarProva() async {
    final alvos = [
      for (final s in pcs)
        if ((s.prova?.on ?? false) && !_travadoPorOutro(s.deviceId)) s.deviceId,
    ];
    if (alvos.isNotEmpty) {
      final rev = _proximoRev();
      final erro = await _gravarEstados({
        for (final id in alvos) id: _setExamPara(id, on: false, rev: rev),
      });
      if (erro != null) return erro;
      final e = Entrega(
        tipo: TipoEntrega.prova,
        enviadoEm: DateTime.now(),
        alvoOn: false,
        revEnviado: rev,
      );
      for (final id in alvos) {
        final s = pcPorId(id);
        if (s == null) continue;
        e.adicionar(id, online: isOnline(s), suportaTurma: suportaTurma(s.versaoExt), comandoNovo: true);
      }
      _novaEntregaDeEstado(e);
    }
    await _session?.definirProva(ProvaDaAula.desligada);
    notifyListeners();
    return null;
  }

  /// Lista da prova mudou (aqui ou noutro celular): regrava state/exam nos
  /// PCs da turma que estão em prova.
  Future<void> _redistribuirProva() async {
    if (!(_session?.prova.on ?? false)) return;
    final alvos = _alvoTurma().where(provaNoPc).toList();
    if (alvos.isEmpty) return;
    final rev = _proximoRev();
    final erro = await _gravarEstados({
      for (final id in alvos) id: _setExamPara(id, on: true, rev: rev),
    });
    if (erro != null) debugPrint('[CdA] redistribuir prova: $erro');
  }

  // ---- Renovação, herança e desligamento ------------------------------------------

  /// A cada 5 min: renova `ate` de trava (+20 min) e prova (+2 h) nos PCs da
  /// turma que ainda estão com o estado vigente. Professor que some deixa a
  /// turma travada no máximo 20 min.
  Future<void> _renovarTurma() async {
    final session = _session;
    if (session == null || _transport == null) return;
    final alvo = _alvoTurma();
    if (session.trava.on) {
      final ids = alvo.where(telaTravada).toList();
      if (ids.isEmpty && (_entregaTrava?.resolvida ?? true)) {
        await session.definirTrava(TravaDaAula.desligada); // venceu sozinha
      } else if (ids.isNotEmpty) {
        final rev = _proximoRev();
        final erro = await _gravarEstados({for (final id in ids) id: _setLockLigado(rev: rev)});
        if (erro != null) debugPrint('[CdA] renovar trava: $erro');
      }
    }
    if (session.prova.on) {
      final ids = alvo.where(provaNoPc).toList();
      if (ids.isEmpty && (_entregaProva?.resolvida ?? true)) {
        await session.definirProva(ProvaDaAula.desligada);
      } else if (ids.isNotEmpty) {
        final rev = _proximoRev();
        final erro = await _gravarEstados({
          for (final id in ids) id: _setExamPara(id, on: true, rev: rev),
        });
        if (erro != null) debugPrint('[CdA] renovar prova: $erro');
      }
    }
    notifyListeners();
  }

  /// PC que entra na aula depois herda a trava e a prova vigentes.
  Future<void> _herdarEstadoDaTurma(String deviceId) async {
    final session = _session;
    // A reserva acabou de ser feita (o stream de /school/aulas ainda pode não
    // ter chegado): basta a aula ativa e o vínculo.
    if (session == null ||
        !session.ativa ||
        session.alunoDe(deviceId) == null ||
        deviceId == _pcProfessorId) {
      return;
    }
    final cmds = <String, Map<String, dynamic>>{};
    if (session.trava.on) cmds['lock'] = _setLockLigado();
    if (session.prova.on) cmds['exam'] = _setExamPara(deviceId, on: true, rev: _proximoRev());
    for (final cmd in cmds.values) {
      final erro = await _gravarEstados({deviceId: cmd});
      if (erro != null) debugPrint('[CdA] herdar estado em $deviceId: $erro');
    }
  }

  /// PC saiu da aula: desliga trava e prova nele, se ligadas.
  Future<void> _desligarEstadoNoPc(String deviceId) async {
    final s = pcPorId(deviceId);
    if (s == null || _travadoPorOutro(deviceId)) return;
    final rev = _proximoRev();
    if (s.trava?.on ?? false) {
      final erro = await _gravarEstados({deviceId: _setLockDesligado(deviceId, rev)});
      if (erro != null) debugPrint('[CdA] destravar $deviceId: $erro');
    }
    if (s.prova?.on ?? false) {
      final erro = await _gravarEstados({deviceId: _setExamPara(deviceId, on: false, rev: rev)});
      if (erro != null) debugPrint('[CdA] tirar $deviceId da prova: $erro');
    }
  }

  /// "Encerrar aula": `on:false` de trava e prova a todo PC com o estado
  /// ligado (inclusive sem aluno vinculado), menos os de outro professor.
  Future<void> _desligarTravaEProvaDeTodos() async {
    final travados = [
      for (final s in pcs)
        if ((s.trava?.on ?? false) && !_travadoPorOutro(s.deviceId)) s.deviceId,
    ];
    final emProva = [
      for (final s in pcs)
        if ((s.prova?.on ?? false) && !_travadoPorOutro(s.deviceId)) s.deviceId,
    ];
    final transport = _transport;
    if (transport == null) return;
    final rev = _proximoRev();
    // Mesmo sem rede: o SDK guarda e manda ao reconectar (e o prazo de 20 min
    // / 2 h destrava sozinho se nunca chegar). Sem rede não espera.
    final escritas = Future.wait([
      for (final id in travados)
        transport.setStateOne(id, _setLockDesligado(id, rev)).catchError((Object e) {
          debugPrint('[CdA] encerrar: destravar $id: $e');
        }),
      for (final id in emProva)
        transport.setStateOne(id, _setExamPara(id, on: false, rev: rev)).catchError((Object e) {
          debugPrint('[CdA] encerrar: prova em $id: $e');
        }),
    ]);
    if (transport.conectado) {
      await escritas.timeout(const Duration(seconds: 15), onTimeout: () => const []);
    }
    _entregaTrava = null;
    _entregaProva = null;
  }

  // ---- Grade de miniaturas ---------------------------------------------------------

  Timer? _gradeTimer;
  final Set<String> _gradePcs = {};
  int? _gradeAbertaEm;

  /// Erro da última renovação da grade (texto pronto), ou null.
  String? erroGrade;

  bool get gradeAberta => _gradeTimer != null;

  /// Quando a grade abriu (ms do servidor): miniatura mais velha que isto
  /// conta como "Carregando…".
  int? get gradeAbertaEm => _gradeAbertaEm;

  Miniatura? miniaturaDe(String deviceId) => pcPorId(deviceId)?.thumb;

  /// Abre a grade: assina /thumbs dos PCs da turma e renova state/monitor a
  /// cada 10 s (ate = agora + 30 s). null = ok.
  Future<String?> abrirGrade() async {
    final sem = motivoSemTurma;
    if (sem != null) return sem;
    _gradeAbertaEm = agoraServidorMs();
    _gradeTimer?.cancel();
    _gradeTimer = Timer.periodic(kMonitorRenova, (_) => _renovarGrade());
    return _renovarGrade();
  }

  Future<String?> _renovarGrade() async {
    final transport = _transport;
    if (transport == null || _gradeTimer == null) return null;
    final alvos = _alvoTurma();
    for (final id in _gradePcs.difference(alvos.toSet()).toList()) {
      await _pararMonitorEm(id); // saiu da turma (ou foi reservado por outro)
    }
    // A grade pode ter fechado durante o await: não reassina nem regrava.
    if (_gradeTimer == null) return null;
    for (final id in alvos) {
      transport.assinarThumb(id);
      _gradePcs.add(id);
    }
    final rev = _proximoRev();
    final ate = agoraServidorMs() + kMonitorAte.inMilliseconds;
    final erro = await _gravarEstados({
      for (final id in alvos) id: buildSetMonitor(rev: rev, ate: ate),
    });
    if (erro != erroGrade) {
      erroGrade = erro;
      notifyListeners();
    }
    return erro;
  }

  Future<void> _pararMonitorEm(String deviceId) async {
    final transport = _transport;
    _gradePcs.remove(deviceId);
    if (transport == null) return;
    transport.cancelarThumb(deviceId);
    // PC que passou para a aula de outro professor: a grade dele é dele (o
    // nosso state/monitor vence sozinho em ≤ 30 s).
    if (_travadoPorOutro(deviceId)) return;
    final escritas = [
      for (final apagar in [transport.apagarMonitor, transport.apagarThumb])
        apagar(deviceId).catchError((Object e) {
          debugPrint('[CdA] fechar grade em $deviceId: $e');
        }),
    ];
    // Sem rede o SDK guarda os deletes e manda ao reconectar: não prende a
    // tela (nem o "Encerrar aula") esperando.
    if (!transport.conectado) return;
    await Future.wait(escritas).timeout(
      const Duration(seconds: 10),
      onTimeout: () => const [],
    );
  }

  /// Fecha a grade (sair da tela, app em segundo plano): para a renovação e
  /// apaga state/monitor e as miniaturas — o PC para de capturar.
  Future<void> fecharGrade() async {
    final tinha = _gradeTimer != null || _gradePcs.isNotEmpty;
    _gradeTimer?.cancel();
    _gradeTimer = null;
    _gradeAbertaEm = null;
    erroGrade = null;
    await Future.wait([for (final id in _gradePcs.toList()) _pararMonitorEm(id)]);
    if (tinha) notifyListeners();
  }

  Future<void> stop() async {
    await fecharGrade();
    await pararServicoAula();
    await _transport?.stop();
  }

  @override
  void dispose() {
    _gradeTimer?.cancel();
    _entregaTimer?.cancel();
    _entregaTravaTimer?.cancel();
    _entregaProvaTimer?.cancel();
    for (final t in _semRespostaTimers) {
      t.cancel();
    }
    _notifyTimer?.cancel();
    _classViewTimer?.cancel();
    _classViewHeartbeat?.cancel();
    _versaoTimer?.cancel();
    _versaoTimer = null;
    _lockHeartbeat?.cancel();
    super.dispose();
  }
}
