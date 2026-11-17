// Modo monitora (docs/protocolo.md §3.1): a sala e o carrinho, pelo canal
// devices/{id}/mon com a chave da monitora, e o histórico em
// archive/{id}/navmon. Nada aqui lê ou decifra o que é do professor: as rules
// negam e o PC recusa o que não é da monitora.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../cloud/archive_store.dart';
import '../cloud/monitoras.dart';
import '../cloud/server_clock.dart';
import '../cloud/session_registry.dart' show kJanelaOnline;
import '../commands/command.dart';
import '../secure/crypto.dart';
import '../secure/keypair.dart';

/// Abaixo disto, fora da tomada, o PC vai para o topo do carrinho.
const int kBateriaBaixa = 30;

const Duration kEsperaDoPc = Duration(seconds: 25);

final RegExp _rotuloDaUnidade = RegExp(r'^Unidade ([0-9]{1,4})$');

enum EstadoMonitora { carregando, semAcesso, pronto }

class PcDaMonitora {
  PcDaMonitora(this.id);

  final String id;
  String? nome;
  int? numeroDoBind;
  int? lastSeen;
  int? bateria;
  bool? naTomada;
  bool? contaAberta;
  int? cargaEm;
  String? _pub;
  SessionCrypto? _cripto;

  // O PC regrava "Unidade N" no rótulo a cada troca de número; bind/numero é
  // o do pareamento e fica velho.
  int? get numero {
    final m = _rotuloDaUnidade.firstMatch(nome ?? '');
    return m != null ? int.parse(m.group(1)!) : numeroDoBind;
  }

  bool get temChave => _cripto != null;

  String get titulo => numero != null ? 'Unidade $numero' : (nome ?? 'Computador');
}

/// Resultado de um pedido: ok, ou o código de erro do ack (ou `sem_resposta`).
typedef RespostaDoPc = ({bool ok, String? erro});

class MonitoraController extends ChangeNotifier {
  MonitoraController({
    RealtimeDb? database,
    SchoolMonitoras? monitoras,
    RelogioDoServidor? relogio,
    this.espera = kEsperaDoPc,
  })  : _db = database ?? Backend.instance.db,
        _monitoras = monitoras ?? SchoolMonitoras(database: database),
        _relogio = relogio ?? RelogioDoServidor();

  final RealtimeDb _db;
  final SchoolMonitoras _monitoras;
  final RelogioDoServidor _relogio;
  final Duration espera;

  EstadoMonitora estado = EstadoMonitora.carregando;
  final Map<String, PcDaMonitora> _pcs = {};
  final Map<String, List<StreamSubscription<DbEvent>>> _porPc = {};
  final List<StreamSubscription<DbEvent>> _gerais = [];
  DeviceKeyPair? _chave;
  int _ultimoSid = 0;
  bool _parado = false;

  int get agoraMs => _relogio.agora().millisecondsSinceEpoch;

  List<PcDaMonitora> get pcs {
    final lista = _pcs.values.toList()
      ..sort((a, b) {
        final n = (a.numero ?? 1 << 30).compareTo(b.numero ?? 1 << 30);
        return n != 0 ? n : (a.nome ?? a.id).compareTo(b.nome ?? b.id);
      });
    return lista;
  }

  bool ligado(PcDaMonitora pc) => pc.lastSeen != null && agoraMs - pc.lastSeen! < kJanelaOnline.inMilliseconds;

  Future<void> start() async {
    _parado = false;
    _gerais.add(
      _db.ref('.info/serverTimeOffset').onValue.listen((e) => _relogio.aoReceberOffset(e.snapshot.value)),
    );
    _gerais.add(_db.ref('.info/connected').onValue.listen((e) => _relogio.aoMudarConexao(e.snapshot.value)));
    try {
      _chave = await _monitoras.baixarChave();
    } on FirebaseException catch (e) {
      debugPrint('[CdA] chave da monitora: ${e.code}');
    }
    if (_parado) return;
    if (_chave == null) {
      estado = EstadoMonitora.semAcesso;
      notifyListeners();
      return;
    }
    _gerais.add(
      _db.ref('school/devices').onValue.listen(
        (e) => _sincronizarRoster(e.snapshot.value),
        onError: (Object e) {
          estado = EstadoMonitora.semAcesso;
          notifyListeners();
        },
      ),
    );
  }

  Future<void> stop() async {
    _parado = true;
    for (final s in [..._gerais, for (final l in _porPc.values) ...l]) {
      await s.cancel();
    }
    _gerais.clear();
    _porPc.clear();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  void _sincronizarRoster(Object? valor) {
    final ids = <String>{
      if (valor is Map)
        for (final e in valor.entries)
          if (e.value == true) '${e.key}',
    };
    for (final id in _pcs.keys.toList()) {
      if (ids.contains(id)) continue;
      for (final s in _porPc.remove(id) ?? const []) {
        unawaited(s.cancel());
      }
      _pcs.remove(id);
    }
    for (final id in ids) {
      if (_pcs.containsKey(id)) continue;
      final pc = _pcs[id] = PcDaMonitora(id);
      _porPc[id] = [
        _ouvir('devices/$id/meta', (v) async {
          if (v is! Map) return;
          pc.nome = v['label'] is String ? v['label'] as String : null;
          final pub = v['pub'];
          if (pub is String && pub != pc._pub) {
            pc._pub = pub;
            pc._cripto = await _derivar(pub);
            await _abrirCarga(pc, (await _db.ref('devices/$id/mon/carga').get()).value);
          }
        }),
        _ouvir('devices/$id/bind/numero', (v) async => pc.numeroDoBind = v is num ? v.toInt() : null),
        _ouvir('devices/$id/presence/lastSeen', (v) async => pc.lastSeen = v is num ? v.toInt() : null),
        _ouvir('devices/$id/mon/carga', (v) => _abrirCarga(pc, v)),
      ];
    }
    estado = EstadoMonitora.pronto;
    notifyListeners();
  }

  StreamSubscription<DbEvent> _ouvir(String caminho, Future<void> Function(Object?) aplicar) =>
      _db.ref(caminho).onValue.listen(
        (e) async {
          await aplicar(e.snapshot.value);
          if (!_parado) notifyListeners();
        },
        onError: (Object e) => debugPrint('[CdA] $caminho: $e'),
      );

  Future<SessionCrypto?> _derivar(String pubDoPc) async {
    final chave = _chave;
    if (chave == null) return null;
    try {
      return SessionCrypto(await chave.deriveSessionKey(pubFromB64url(pubDoPc)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _abrirCarga(PcDaMonitora pc, Object? valor) async {
    final cripto = pc._cripto;
    if (cripto == null || valor is! Map || valor['env'] is! String) return;
    try {
      final msg = await cripto.open(valor['env'] as String);
      if (msg['type'] != MessageType.cargaReport) return;
      final nivel = msg['level'];
      pc.bateria = nivel is num && nivel >= 0 && nivel <= 100 ? nivel.toInt() : null;
      pc.naTomada = msg['plugged'] is bool ? msg['plugged'] as bool : null;
      pc.contaAberta = msg['session'] is bool ? msg['session'] as bool : null;
      pc.cargaEm = valor['ts'] is num ? (valor['ts'] as num).toInt() : null;
    } catch (_) {
      // Envelope de outra chave (troca em andamento): espera o próximo.
    }
  }

  /// Manda um pedido pelo canal da monitora e espera o ack do PC.
  Future<RespostaDoPc> enviar(PcDaMonitora pc, String tipo, Map<String, dynamic> payload) async {
    final cripto = pc._cripto;
    if (cripto == null) return (ok: false, erro: 'sem_chave');
    final agora = agoraMs;
    _ultimoSid = agora > _ultimoSid ? agora : _ultimoSid + 1;
    final id = 'm$_ultimoSid';
    final env = await cripto.seal({
      'sid': _ultimoSid,
      'seq': 1,
      'ts': agora,
      'v': 1,
      'type': tipo,
      'id': id,
      'payload': payload,
    });
    final cmd = _db.ref('devices/${pc.id}/mon/cmd').push();
    try {
      await cmd.set(env);
    } on FirebaseException catch (e) {
      return (ok: false, erro: e.code == 'permission-denied' ? 'negado' : 'sem_internet');
    }
    final ackRef = _db.ref('devices/${pc.id}/mon/ack/${cmd.key}');
    try {
      final evento = await ackRef.onValue.firstWhere((e) => e.snapshot.value is String).timeout(espera);
      unawaited(ackRef.remove().catchError((Object _) {}));
      final ack = await cripto.open(evento.snapshot.value as String);
      if (ack['id'] != id) return (ok: false, erro: 'payload_invalido');
      return (ok: ack['ok'] == true, erro: ack['error'] is String ? ack['error'] as String : null);
    } on TimeoutException {
      unawaited(cmd.remove().catchError((Object _) {}));
      return (ok: false, erro: 'sem_resposta');
    } catch (_) {
      return (ok: false, erro: 'payload_invalido');
    }
  }

  /// Foto da tela agora: null se o PC recusou ou não respondeu ([erro] diz por quê).
  Future<({Uint8List? jpeg, String? erro})> verTela(PcDaMonitora pc) async {
    final r = await enviar(pc, MessageType.captureScreen, const {});
    if (!r.ok) return (jpeg: null, erro: r.erro);
    final ref = _db.ref('devices/${pc.id}/mon/snapshot');
    try {
      final snap = (await ref.get()).value;
      unawaited(ref.remove().catchError((Object _) {}));
      if (snap is! Map || snap['env'] is! String || pc._cripto == null) {
        return (jpeg: null, erro: 'snapshot_upload');
      }
      final msg = await pc._cripto!.open(snap['env'] as String);
      if (msg['type'] != MessageType.screenSnapshot || msg['jpegB64'] is! String) {
        return (jpeg: null, erro: 'snapshot_upload');
      }
      return (jpeg: base64.decode(msg['jpegB64'] as String), erro: null);
    } catch (_) {
      return (jpeg: null, erro: 'snapshot_upload');
    }
  }

  /// Dias do histórico (hoje e os 14 anteriores), pelo relógio do servidor.
  List<String> diasDoHistorico() => recentDays(agoraMs);

  /// Histórico de um dia pela cópia da monitora. null = PC ainda sem a chave
  /// dela; lança em erro de leitura (rede/permissão).
  Future<ArchivedDay?> historico(PcDaMonitora pc, String dia) async {
    final cripto = pc._cripto;
    if (cripto == null) return null;
    final snap = await _db.ref('archive/${pc.id}/navmon/$dia').get();
    return parseNavDay(snap.value, cripto);
  }

  Future<RespostaDoPc> mensagem(PcDaMonitora pc, String texto) =>
      enviar(pc, MessageType.showMessage, {'title': 'Mensagem da monitora', 'body': texto});

  Future<RespostaDoPc> fecharAbas(PcDaMonitora pc) => enviar(pc, MessageType.closeAllTabs, const {});

  Future<RespostaDoPc> energia(PcDaMonitora pc, AcaoEnergia acao) =>
      enviar(pc, MessageType.energia, {'acao': acao.name});

  /// A mesma ação em todos os PCs ligados; devolve quantos confirmaram.
  Future<({int ok, int total})> paraTodosLigados(
    Future<RespostaDoPc> Function(PcDaMonitora pc) acao,
  ) async {
    final alvo = pcs.where(ligado).toList();
    final respostas = await Future.wait(alvo.map(acao));
    return (ok: respostas.where((r) => r.ok).length, total: alvo.length);
  }
}
