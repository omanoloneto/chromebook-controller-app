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
import '../service/notification_service.dart';
import 'class_session_store.dart';
import 'favorites_store.dart';
import 'name_store.dart';
import 'rules_store.dart';
import 'students_store.dart';

class PairingController extends ChangeNotifier {
  PairingController({this.deviceName = 'Professor'});

  /// Nome do professor (popup da extensão). Alterável em Ajustes.
  String deviceName;

  FirebaseTransport? _transport;
  NameStore? _names;
  RulesStore? _rules;
  FavoritesStore? _favorites;
  StudentsStore? _students;
  ClassSessionStore? _session;
  Timer? _notifyTimer;
  int _ultimoOnline = -1;
  String? _wallpaperHash;

  /// Estado de inicialização (a UI observa; start() não lança).
  bool iniciando = true;
  String? erroDeConexao;

  /// Notificações com som (alerta/bloqueio). Sincronizado pelo root a partir
  /// das preferências (Ajustes).
  bool notificarSites = true;

  /// Injetado pelo root (main.dart) antes do start().
  NotificationService? notificacoes;

  Future<void> start() async {
    if (_transport != null) return; // idempotente (retry não duplica listeners)
    try {
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
      transport.registry.onNovosEventos = _onNovosEventos;
      await transport.start();
      _transport = transport;
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
  // set_wallpaper se houver imagem publicada.
  List<Map<String, dynamic>> _comandosDeEstado(String deviceId) {
    return [
      if (_rules != null)
        buildSetRules(_regrasParaDevice(deviceId), rev: _proximoRev()),
      if (_wallpaperHash != null) buildSetWallpaper(_wallpaperHash!),
    ];
  }

  /// Regras válidas para um PC = regras da casa − liberações desta aula.
  List<DomainRule> _regrasParaDevice(String deviceId) {
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
    final agora = DateTime.now().millisecondsSinceEpoch;
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
      if (r.action == RuleAction.block) {
        notifs.notificarBloqueado(pc: nomePc, dominio: dominio);
      } else {
        notifs.notificarAlerta(pc: nomePc, dominio: dominio);
      }
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

  /// Encerra a aula: fecha o NAVEGADOR (todas as janelas) em todos os PCs,
  /// limpa os vínculos aluno↔PC e derruba as liberações (o bloqueio integral
  /// volta a valer nos PCs que tinham exceção).
  Future<void> encerrarAula() async {
    await _transport?.sendToAll(buildCloseAllTabs(closeWindows: true));
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
    super.dispose();
  }
}
