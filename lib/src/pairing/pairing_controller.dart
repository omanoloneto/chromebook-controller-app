// Orquestra o transporte Firebase: carrega o par de chaves do professor,
// autentica (Auth anônima), liga o FirebaseTransport e expõe a lista de PCs +
// comandos + nomes + regras + favoritos + papel de parede. É um
// ChangeNotifier: as telas observam.

import 'dart:async';

import 'package:crypto/crypto.dart' as c;
import 'package:firebase_auth/firebase_auth.dart'; // também exporta FirebaseException
import 'package:flutter/foundation.dart';

import '../cloud/firebase_transport.dart';
import '../cloud/qr_payload.dart';
import '../cloud/session_registry.dart';
import '../commands/command.dart';
import '../commands/domain_rules.dart';
import '../secure/key_store.dart';
import '../service/foreground_service.dart';
import 'class_session_store.dart';
import 'favorites_store.dart';
import 'name_store.dart';
import 'rules_store.dart';
import 'students_store.dart';

class PairingController extends ChangeNotifier {
  PairingController({this.deviceName = 'Professor'});

  final String deviceName;
  FirebaseTransport? _transport;
  NameStore? _names;
  RulesStore? _rules;
  FavoritesStore? _favorites;
  StudentsStore? _students;
  ClassSessionStore? _session;
  Timer? _notifyTimer;
  int _ultimoOnline = -1;
  String? _wallpaperHash;

  Future<void> start() async {
    final teacher = await KeyStore.loadOrCreate();
    _names = await NameStore.load();
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
    await transport.start();
    _transport = transport;
    await iniciarServicoAula();
  }

  // Comandos de estado vigentes (gravados em state/* a cada pareamento):
  // set_rules SEMPRE (mesmo vazio, para limpar regras antigas no cliente);
  // set_wallpaper se houver imagem publicada.
  List<Map<String, dynamic>> _comandosDeEstado() {
    final rules = _rules;
    return [
      if (rules != null) buildSetRules(rules.regras, rev: rules.rev),
      if (_wallpaperHash != null) buildSetWallpaper(_wallpaperHash!),
    ];
  }

  // Domínio da primeira aba que casa regra `alert` OU `block` (aba bloqueada
  // ainda aberta = enforcement falhou — o professor precisa ver).
  String? _avaliarAlerta(List<TabInfo> tabs) {
    final regras = _rules?.regras;
    if (regras == null || regras.isEmpty) return null;
    for (final t in tabs) {
      final r = acharRegra(regras, t.url);
      if (r != null) {
        try {
          return Uri.parse(t.url).host;
        } catch (_) {
          return r.pattern;
        }
      }
    }
    return null;
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
      await transport.pairDevice(qr);
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
    await _transport?.forgetDevice(deviceId);
    notifyListeners();
  }

  // ---- Comandos ---------------------------------------------------------------

  /// Abre uma URL em TODOS os PCs (turma toda).
  void abrirEmTodos(String url) {
    _transport?.sendToAll(buildOpenUrl(url));
  }

  /// Abre uma URL em um PC específico.
  void abrirEm(String deviceId, String url) {
    _transport?.sendCommand(deviceId, buildOpenUrl(url));
  }

  /// Fecha uma aba específica (URL exata) em um PC.
  void fecharAbaEm(String deviceId, String url) {
    _transport?.sendCommand(deviceId, buildCloseTabs(url: url));
  }

  /// Fecha todas as abas de um domínio na turma toda.
  void fecharSiteEmTodos(String domain) {
    _transport?.sendToAll(buildCloseTabs(domain: domain));
  }

  /// Fecha todas as abas de um domínio em um PC.
  void fecharSiteEm(String deviceId, String domain) {
    _transport?.sendCommand(deviceId, buildCloseTabs(domain: domain));
  }

  /// Fecha TODAS as abas da turma toda (deixa 1 aba vazia em cada PC).
  void fecharTodasAsAbasEmTodos() {
    _transport?.sendToAll(buildCloseAllTabs());
  }

  /// Fecha TODAS as abas de um PC (deixa 1 aba vazia).
  void fecharTodasAsAbasEm(String deviceId) {
    _transport?.sendCommand(deviceId, buildCloseAllTabs());
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
    notifyListeners();
  }

  Future<void> vincularAluno(String deviceId, String aluno) async {
    await _session?.vincular(deviceId, aluno);
    notifyListeners();
  }

  Future<void> desvincularAluno(String deviceId) async {
    await _session?.desvincular(deviceId);
    notifyListeners();
  }

  /// Encerra a aula: fecha o NAVEGADOR (todas as janelas) em todos os PCs e
  /// limpa os vínculos aluno↔PC desta sessão.
  Future<void> encerrarAula() async {
    await _transport?.sendToAll(buildCloseAllTabs(closeWindows: true));
    await _session?.encerrar();
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
    final rules = _rules;
    if (rules == null) return;
    _transport?.setStateAll(buildSetRules(rules.regras, rev: rules.rev));
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
    super.dispose();
  }
}
