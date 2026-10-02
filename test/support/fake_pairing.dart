// PairingController de mentira para os testes de tela (D2): os PCs ficam num
// mapa em memória, a hora do servidor é fixa e as ações só anotam a chamada.
// Nada aqui fala com o Firebase.

import 'dart:typed_data';

import 'package:controle_de_aula/src/cloud/conversa.dart';
import 'package:controle_de_aula/src/cloud/entrega.dart';
import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/pairing/pairing_controller.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/util/versao.dart';

/// Hora fixa do "servidor" nos testes: 2/10/2026 10:42 (hora local).
final int kAgoraTeste = DateTime(2026, 10, 2, 10, 42).millisecondsSinceEpoch;

class FakePairing extends PairingController {
  FakePairing() : super(deviceName: 'Professora');

  final Map<String, PcSession> mapa = {};
  final Map<String, String> nomes = {};
  final Set<String> desligados = {};
  final Map<String, String> outrosProfessores = {};
  final Set<String> semProfessor = {};
  final Set<String> travados = {};
  final Set<String> emProva = {};
  List<String> turma = [];
  String? semTurma;
  int agora = kAgoraTeste;
  List<String> padroes = [];
  List<String> silenciados = [];
  bool provaLigadaFake = false;
  bool travaLigadaFake = false;

  // Entregas (faixa).
  Entrega? entregaFake;
  String? entregaUmPcFake;
  Entrega? entregaTravaFake;
  Entrega? entregaProvaFake;

  // Grade.
  int? abertaEm;
  String? erroGradeFake;
  int abrirGradeChamadas = 0;
  int fecharGradeChamadas = 0;

  // O que as ações receberam.
  final List<(String, String)> chatsEnviados = [];
  String? erroDoChat;
  final List<(PedidoLiberacao, String?)> recusados = [];
  final List<(PedidoLiberacao, List<String>?)> liberados = [];
  final List<String> maosBaixadas = [];
  final List<String> conversasAbertas = [];

  /// Põe um PC no mapa (e na turma, se [naTurma]).
  PcSession pc(
    String id, {
    String? nome,
    String ext = '0.7.0',
    bool online = true,
    bool naTurma = true,
  }) {
    final s = PcSession(
      deviceId: id,
      label: id,
      crypto: SessionCrypto(List.filled(32, 0)),
    )..versaoExt = ext;
    mapa[id] = s;
    if (nome != null) nomes[id] = nome;
    if (!online) desligados.add(id);
    if (naTurma) turma.add(id);
    return s;
  }

  void avisar() => notifyListeners();

  @override
  List<PcSession> get pcs => mapa.values.toList();
  @override
  PcSession? pcPorId(String deviceId) => mapa[deviceId];
  @override
  bool isOnline(PcSession s) => !desligados.contains(s.deviceId);
  @override
  bool carregandoPc(String deviceId) => false;
  @override
  int agoraServidorMs() => agora;
  @override
  String nomeDe(PcSession s) => nomes[s.deviceId] ?? s.label;
  @override
  String nomeDoPc(String deviceId) => nomes[deviceId] ?? deviceId;
  @override
  String? alunoDe(String deviceId) => null;
  @override
  List<String> get pcsDaTurma => turma;
  @override
  String? get motivoSemTurma => semTurma;
  @override
  String? professorQueTravou(String deviceId) => outrosProfessores[deviceId];
  @override
  bool telaTravada(String deviceId) => travados.contains(deviceId);
  @override
  bool travadaSemProfessor(String deviceId) =>
      travados.contains(deviceId) && semProfessor.contains(deviceId);
  @override
  bool provaNoPc(String deviceId) => emProva.contains(deviceId);
  @override
  bool get provaLigada => provaLigadaFake;
  @override
  bool get travaLigada => travaLigadaFake;
  @override
  DateTime? get travaDesde => null;

  // ---- Recados -----------------------------------------------------------
  @override
  List<PedidoLiberacao> get pedidosPendentes => [
        for (final s in mapa.values) ...s.pedidos,
      ]..sort((a, b) => a.ts.compareTo(b.ts));
  @override
  List<PcSession> get maosLevantadas =>
      mapa.values.where((s) => maoLevantada(s.deviceId)).toList();
  @override
  bool maoLevantada(String deviceId) {
    final em = mapa[deviceId]?.maoEm;
    return em != null &&
        agora - em < const Duration(minutes: 10).inMilliseconds;
  }

  @override
  List<PcSession> get conversas =>
      mapa.values.where((s) => s.chat.isNotEmpty).toList()
        ..sort((a, b) => b.chat.last.ts.compareTo(a.chat.last.ts));
  @override
  List<String> get pcsSilenciados => silenciados;
  @override
  List<String> padroesParaLiberar(PedidoLiberacao pedido) => padroes;

  @override
  Future<String?> liberarPedido(
    PedidoLiberacao pedido, {
    List<String>? padroes,
  }) async {
    liberados.add((pedido, padroes));
    mapa[pedido.deviceId]?.pedidos.remove(pedido);
    notifyListeners();
    return null;
  }

  @override
  Future<String?> recusarPedido(
    PedidoLiberacao pedido, {
    String? motivo,
  }) async {
    recusados.add((pedido, motivo));
    mapa[pedido.deviceId]?.pedidos.remove(pedido);
    notifyListeners();
    return null;
  }

  @override
  Future<void> baixarMao(String deviceId) async {
    maosBaixadas.add(deviceId);
    mapa[deviceId]?.maoEm = null;
    notifyListeners();
  }

  // ---- Conversa ----------------------------------------------------------
  @override
  Future<void> abrirConversa(String deviceId) async {
    conversasAbertas.add(deviceId);
    mapa[deviceId]?.naoLidas = 0;
  }

  @override
  Future<String?> enviarChat(String deviceId, String texto) async {
    chatsEnviados.add((deviceId, texto));
    if (erroDoChat != null) return erroDoChat;
    mapa[deviceId]?.chat.add(
          ChatItem(
            id: 'm${chatsEnviados.length}',
            autor: AutorChat.professor,
            texto: texto.trim(),
            ts: agora,
            estado: EstadoBalao.enviando,
          ),
        );
    notifyListeners();
    return null;
  }

  // ---- Trava e prova -----------------------------------------------------
  final List<({String texto, bool mute, Set<String>? apenas})> travas = [];
  int destravarTurmaChamadas = 0;
  final List<String> destravados = [];
  List<String> sites = [];
  int ligarProvaChamadas = 0;
  int desligarProvaChamadas = 0;

  @override
  Future<String?> travarTurma({
    required String texto,
    bool mute = true,
    Iterable<String>? apenas,
  }) async {
    travas.add((texto: texto, mute: mute, apenas: apenas?.toSet()));
    return null;
  }

  @override
  Future<String?> destravarTurma() async {
    destravarTurmaChamadas++;
    return null;
  }

  @override
  Future<String?> destravarPc(String deviceId) async {
    destravados.add(deviceId);
    return null;
  }

  @override
  List<String> get sitesProva => sites;
  @override
  List<PcSession> get pcsSemModoProva => [
        for (final id in turma)
          if (mapa[id] case final s? when !suportaTurma(s.versaoExt)) s,
      ];

  @override
  Future<String?> ligarProva() async {
    ligarProvaChamadas++;
    provaLigadaFake = true;
    notifyListeners();
    return null;
  }

  @override
  Future<String?> desligarProva() async {
    desligarProvaChamadas++;
    provaLigadaFake = false;
    notifyListeners();
    return null;
  }

  // ---- Grade -------------------------------------------------------------
  bool gradeAbertaFake = false;

  @override
  bool get gradeAberta => gradeAbertaFake;

  // Como o controller: sem turma, recusa (e não abre).
  @override
  Future<String?> abrirGrade() async {
    abrirGradeChamadas++;
    if (semTurma != null) return semTurma;
    gradeAbertaFake = true;
    abertaEm ??= agora - 60000;
    return null;
  }

  @override
  Future<void> fecharGrade() async {
    fecharGradeChamadas++;
    gradeAbertaFake = false;
  }

  final List<String> fotosDeTela = [];

  @override
  Future<Uint8List?> tirarFotoTela(String deviceId) async {
    fotosDeTela.add(deviceId);
    return null; // a tela inteira não veio
  }

  @override
  int? get gradeAbertaEm => abertaEm;
  @override
  String? get erroGrade => erroGradeFake;
  @override
  Miniatura? miniaturaDe(String deviceId) => mapa[deviceId]?.thumb;

  // ---- Entregas ----------------------------------------------------------
  @override
  Entrega? get entrega => entregaFake;
  @override
  String? get entregaUmPc => entregaUmPcFake;
  @override
  String? get textoDaEntrega {
    final e = entregaFake;
    if (e == null) return null;
    final um = entregaUmPcFake;
    return um == null ? textoEntrega(e) : textoEntregaUmPc(e, nomeDoPc(um));
  }

  @override
  Entrega? get entregaTrava => entregaTravaFake;
  @override
  String? get textoDaTrava =>
      entregaTravaFake == null ? null : textoTrava(entregaTravaFake!);
  @override
  Entrega? get entregaProva => entregaProvaFake;
  @override
  String? get textoDaProva =>
      entregaProvaFake == null ? null : textoProva(entregaProvaFake!);
  @override
  String textoDaEntregaNoPc(Entrega e, EntregaPc p) =>
      '${nomeDoPc(p.deviceId)} — ${textoDoPc(e, p)}';
}

/// Uma mensagem da conversa (hora = [kAgoraTeste] + [min] minutos).
ChatItem msg(
  String id,
  AutorChat autor,
  String texto, {
  int min = 0,
  EstadoBalao? estado,
  bool paraTurma = false,
}) =>
    ChatItem(
      id: id,
      autor: autor,
      texto: texto,
      ts: kAgoraTeste + min * 60000,
      estado: estado,
      paraTurma: paraTurma,
    );
