// Orquestra o transporte Firebase: carrega o par de chaves do professor,
// autentica (Auth anônima), liga o FirebaseTransport e expõe a lista de PCs +
// comandos + nomes + regras + favoritos + papel de parede. É um
// ChangeNotifier: as telas observam.

import 'dart:async';

import 'package:crypto/crypto.dart' as c;
import 'package:firebase_auth/firebase_auth.dart'; // também exporta FirebaseException
import 'package:firebase_database/firebase_database.dart' show FirebaseDatabase;
import 'package:flutter/foundation.dart';

import 'package:google_sign_in/google_sign_in.dart';

import '../cloud/backup_store.dart';
import '../cloud/broadcast_target.dart';
import '../cloud/firebase_transport.dart';
import '../cloud/history_store.dart';
import '../cloud/qr_payload.dart';
import '../cloud/session_registry.dart';
import '../commands/class_view.dart';
import '../commands/command.dart';
import '../commands/domain_rules.dart';
import '../secure/history_crypto.dart';
import '../secure/key_store.dart';
import '../service/foreground_service.dart';
import '../service/notification_service.dart';
import 'class_session_store.dart';
import 'favorites_store.dart';
import 'name_store.dart';
import 'rules_store.dart';
import 'students_store.dart';
import 'unit_store.dart';

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
  StudentsStore? _students;
  ClassSessionStore? _session;
  Timer? _notifyTimer;
  int _ultimoOnline = -1;
  String? _wallpaperHash;

  // Visão da turma no telão: debounce de push + heartbeat + dedupe.
  Timer? _classViewTimer;
  Timer? _classViewHeartbeat;
  String? _classViewFingerprint;

  /// Estado de inicialização (a UI observa; start() não lança).
  bool iniciando = true;
  String? erroDeConexao;

  /// Notificações com som (alerta/bloqueio). Sincronizado pelo root a partir
  /// das preferências (Ajustes).
  bool notificarSites = true;

  /// Injetado pelo root (main.dart) antes do start().
  NotificationService? notificacoes;

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

  /// Abre uma URL só no PC do professor (ex.: link do histórico de um aluno).
  void abrirNoPcProfessor(String url) {
    final id = _pcProfessorId;
    if (id == null) return;
    _transport?.sendCommand(id, buildOpenUrl(url));
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
      _students = await StudentsStore.load();
      _session = await ClassSessionStore.load();

      // Auth anônima: o uid identifica este professor nas Security Rules.
      // Persiste entre execuções; some só se o app for reinstalado (recovery:
      // aluno desvincula pelo popup e re-escaneia).
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      if (user == null) {
        throw StateError('auth_anonima_falhou');
      }

      final transport = FirebaseTransport(
        teacher: teacher,
        teacherUid: user.uid,
        teacherName: deviceName,
      );
      transport.comandosDeEstado = _comandosDeEstado;
      transport.registry.onChange = _scheduleNotify;
      transport.registry.avaliarAlerta = _avaliarAlerta;
      transport.registry.onNovosEventos = _onNovosEventos;
      transport.pcProfessorId = _pcProfessorId;
      transport.registry.pcProfessorId = _pcProfessorId;
      await transport.start();
      _transport = transport;

      // Heartbeat da visão da turma: mantém o "atualizado há Xs" do telão
      // vivo e propaga online→offline (derivado de lastSeen, não gera evento).
      _classViewHeartbeat ??= Timer.periodic(
        const Duration(seconds: 60),
        (_) => _pushClassView(force: true),
      );

      // Histórico de aulas: cifrado com chave derivada da keypair do
      // professor; re-anexa à sessão aberta se o app fechou no meio da aula.
      final hCrypto = await historyCryptoFrom(teacher);
      _history = HistoryStore(teacherUid: user.uid, crypto: hCrypto);
      _backup = BackupStore(uid: user.uid, historyCrypto: hCrypto);
      backupAtivo = await _backup!.existeNaNuvem();
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
      // FlutterFire reconecta sozinho.
      erroDeConexao = 'Não foi possível conectar ao Firebase: $e\n'
          'Verifique a internet do celular.';
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
      return 'Falha ao restaurar: $e';
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
  // set_wallpaper se houver imagem publicada;
  // set_unit se o device já tem número (re-pareamento reescreve state/unit
  // com a chave nova; 1º pareamento sai sem — o bind.numero cobre).
  List<Map<String, dynamic>> _comandosDeEstado(String deviceId) {
    final numero = _units?.numeroDe(deviceId);
    return [
      if (_rules != null)
        buildSetRules(_regrasParaDevice(deviceId), rev: _proximoRev()),
      if (_wallpaperHash != null) buildSetWallpaper(_wallpaperHash!),
      if (numero != null) buildSetUnit(rev: _proximoRev(), numero: numero),
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

  /// Regras válidas para um PC = regras da casa − liberações desta aula.
  /// PC do professor: sem regra nenhuma (o telão precisa abrir qualquer link).
  List<DomainRule> _regrasParaDevice(String deviceId) {
    if (deviceId == _pcProfessorId) return const [];
    final regras = _rules?.regras ?? const <DomainRule>[];
    final liberados = _session?.excecoesDe(deviceId) ?? const <String>{};
    if (liberados.isEmpty) return regras;
    return regras.where((r) => !liberados.contains(r.pattern)).toList();
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
    final regras = _rules?.regras;
    if (regras == null || regras.isEmpty) return;
    final liberados = _session?.excecoesDe(deviceId) ?? const <String>{};
    final s = _transport?.registry.byId(deviceId);
    final nomePc = (s != null ? alunoDe(deviceId) ?? nomeDe(s) : deviceId);
    for (final e in novos) {
      final r = acharRegra(regras, e.url);
      if (r == null || liberados.contains(r.pattern)) continue;
      String dominio;
      try {
        dominio = Uri.parse(e.url).host;
      } catch (_) {
        dominio = r.pattern;
      }
      final bloqueado = r.action == RuleAction.block;
      final futuro = bloqueado
          ? notifs.notificarBloqueado(pc: nomePc, dominio: dominio)
          : notifs.notificarAlerta(pc: nomePc, dominio: dominio);
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

  bool isOnline(PcSession s) =>
      s.online(_transport?.nowServer() ?? DateTime.now());

  /// Nome dado pelo professor, ou o label do aparelho (renomeável no popup).
  String nomeDe(PcSession s) => _names?.nameOf(s.deviceId) ?? s.label;

  /// Salva o nome do aluno para este PC (vazio remove).
  Future<void> renomear(String deviceId, String nome) async {
    await _names?.setName(deviceId, nome);
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
      if (numero != null) await _units?.definir(qr.deviceId, numero);
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
      return 'Falha ao parear: ${e.message ?? e.code}';
    } catch (e) {
      return 'Falha ao parear: $e';
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
    return alvoDeBroadcast(
      aulaAtiva: aulaAtiva,
      vinculados: _session?.vinculos.keys ?? const [],
      todos: (_transport?.registry.all ?? const []).map((s) => s.deviceId),
      pcProfessorId: _pcProfessorId,
    );
  }

  /// Quantos PCs um comando de turma vai atingir agora.
  int get pcsAlvoCount => _devicesAlvo().length;

  Future<void> _enviarParaAlvo(Map<String, dynamic> cmd) async {
    final transport = _transport;
    if (transport == null) return;
    for (final deviceId in _devicesAlvo()) {
      await transport.sendCommand(deviceId, cmd);
    }
  }

  /// Abre uma URL nos PCs alvo (turma, ou só vinculados durante a aula).
  void abrirEmTodos(String url) {
    _enviarParaAlvo(buildOpenUrl(url));
  }

  /// Abre uma URL em um PC específico.
  void abrirEm(String deviceId, String url) {
    _transport?.sendCommand(deviceId, buildOpenUrl(url));
  }

  /// Fecha uma aba específica (URL exata) em um PC.
  void fecharAbaEm(String deviceId, String url) {
    _transport?.sendCommand(deviceId, buildCloseTabs(url: url));
  }

  /// Fecha todas as abas de um domínio nos PCs alvo.
  void fecharSiteEmTodos(String domain) {
    _enviarParaAlvo(buildCloseTabs(domain: domain));
  }

  /// Fecha todas as abas de um domínio em um PC.
  void fecharSiteEm(String deviceId, String domain) {
    _transport?.sendCommand(deviceId, buildCloseTabs(domain: domain));
  }

  /// Fecha TODAS as abas dos PCs alvo (deixa 1 aba vazia em cada).
  void fecharTodasAsAbasEmTodos() {
    _enviarParaAlvo(buildCloseAllTabs());
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
    notifyListeners();
  }

  Future<void> renomearTurma(int indice, String nome) async {
    await _students?.renomearTurma(indice, nome);
    notifyListeners();
  }

  Future<void> removerTurma(int indice) async {
    await _students?.removerTurma(indice);
    notifyListeners();
  }

  Future<void> adicionarAluno(int turmaIndice, String aluno) async {
    await _students?.adicionarAluno(turmaIndice, aluno);
    notifyListeners();
  }

  Future<void> renomearAluno(int turmaIndice, int alunoIndice, String nome) async {
    await _students?.renomearAluno(turmaIndice, alunoIndice, nome);
    notifyListeners();
  }

  Future<void> removerAluno(int turmaIndice, int alunoIndice) async {
    await _students?.removerAluno(turmaIndice, alunoIndice);
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

  Future<void> vincularAluno(String deviceId, String aluno) async {
    await _session?.vincular(deviceId, aluno);
    notifyListeners();
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
    await vincularAluno(deviceId, n);
    return null;
  }

  Future<void> desvincularAluno(String deviceId) async {
    await _session?.desvincular(deviceId);
    notifyListeners();
  }

  /// Encerra a aula: fecha o NAVEGADOR (todas as janelas) em todos os PCs,
  /// limpa os vínculos aluno↔PC e derruba as liberações (o bloqueio integral
  /// volta a valer nos PCs que tinham exceção).
  Future<void> encerrarAula() async {
    // Alvo calculado ANTES de encerrar (encerrar limpa os vínculos).
    await _enviarParaAlvo(buildCloseAllTabs(closeWindows: true));
    await _history?.fecharSessao();
    final comExcecao = _session?.devicesComExcecao ?? const <String>[];
    await _session?.encerrar();
    for (final deviceId in comExcecao) {
      _distribuirRegrasPara(deviceId); // snapshot volta ao completo
    }
    notifyListeners();
  }

  // ---- Regras -------------------------------------------------------------------

  List<DomainRule> get regras => _rules?.regras ?? const [];

  Future<void> adicionarRegra(String pattern, String action) async {
    await _rules?.adicionar(pattern, action);
    _distribuirRegras();
  }

  Future<void> atualizarRegra(int indice, String pattern, String action) async {
    await _rules?.atualizarEm(indice, pattern, action);
    _distribuirRegras();
  }

  Future<void> removerRegra(int indice) async {
    await _rules?.removerEm(indice);
    _distribuirRegras();
  }

  void _distribuirRegras() {
    final transport = _transport;
    if (_rules == null || transport == null) return;
    // Snapshot por PC: liberações da aula variam por device.
    for (final s in transport.registry.all) {
      _distribuirRegrasPara(s.deviceId);
    }
    notifyListeners();
  }

  void _distribuirRegrasPara(String deviceId) {
    _transport?.setStateOne(
      deviceId,
      buildSetRules(_regrasParaDevice(deviceId), rev: _proximoRev()),
    );
  }

  // ---- Liberações por PC (valem só durante a aula) --------------------------------

  /// Padrões de bloqueio liberados para um PC nesta aula.
  Set<String> liberacoesDe(String deviceId) =>
      _session?.excecoesDe(deviceId) ?? const {};

  /// Padrões de bloqueio cadastrados (candidatos a liberação).
  List<String> get padroesBloqueio => [
        for (final r in regras)
          if (r.action == RuleAction.block) r.pattern,
      ];

  /// Libera um padrão bloqueado para UM PC até o fim da aula.
  Future<void> liberarPara(String deviceId, String pattern) async {
    if (!aulaAtiva) return;
    await _session?.liberar(deviceId, pattern);
    _distribuirRegrasPara(deviceId);
    notifyListeners();
  }

  /// Revoga a liberação (o bloqueio volta a valer na hora).
  Future<void> revogarLiberacao(String deviceId, String pattern) async {
    await _session?.revogar(deviceId, pattern);
    _distribuirRegrasPara(deviceId);
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

  String? get wallpaperHash => _wallpaperHash;

  /// Publica o blob no RTDB (compartilhado pela turma) e grava o comando de
  /// estado (só o hash) em cada PC.
  Future<void> definirPapelDeParede(Uint8List bytes) async {
    final transport = _transport;
    if (transport == null) return;
    if (bytes.length > 4 * 1024 * 1024) {
      throw ArgumentError('imagem_grande'); // vira base64 ~5.3MB no banco
    }
    final hash = c.sha256.convert(bytes).toString().substring(0, 8);
    await transport.publishWallpaper(bytes, hash);
    _wallpaperHash = hash;
    await transport.setStateAll(buildSetWallpaper(hash));
    notifyListeners();
  }

  Future<void> stop() async {
    await pararServicoAula();
    await _transport?.stop();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _classViewTimer?.cancel();
    _classViewHeartbeat?.cancel();
    super.dispose();
  }
}
