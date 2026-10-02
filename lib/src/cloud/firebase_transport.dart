// Transporte via Firebase RTDB (protocolo v4) — substitui o ControlServer.
// O app escuta o roster (/teachers/{uid}/devices) e, por PC, os nós report/
// presence/ack/bind/up/state/lock/state/exam. Comandos saem selados
// (AES-256-GCM, cabeçalho {sid,seq,ts}) para cmd/ (fila) ou state/
// (snapshot). Ver docs/protocolo.md.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../commands/command.dart';
import '../secure/keypair.dart';
import '../util/ids.dart';
import 'qr_payload.dart';
import 'server_clock.dart';
import 'session_registry.dart';
import 'up_router.dart';

/// Nó de `state/` de cada comando de estado. Tipo desconhecido LANÇA: cair em
/// 'rules' sobrescreveria as regras do PC com outra coisa.
String noDeEstado(Object? type) => switch (type) {
      MessageType.setRules => 'rules',
      MessageType.setWallpaper => 'wallpaper',
      MessageType.setClassView => 'classview',
      MessageType.setUnit => 'unit',
      MessageType.setLock => 'lock',
      MessageType.setExam => 'exam',
      MessageType.setMonitor => 'monitor',
      _ => throw ArgumentError.value(type, 'type', 'não é comando de estado'),
    };

class FirebaseTransport {
  FirebaseTransport({
    required this.teacher,
    required this.teacherUid,
    this.schoolUid,
    this.teacherName = 'Professor',
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final DeviceKeyPair teacher;
  final String teacherUid;

  /// Workspace da escola ativo (null = modo isolado, comportamento clássico).
  /// No workspace: roster único em /school/devices, bind.teacherUid = uid da
  /// escola (o wallpaper continua num caminho só — a extensão não muda) e o
  /// roster pessoal segue gravado em paralelo (rollback p/ versões antigas).
  final String? schoolUid;

  String get _donoUid => schoolUid ?? teacherUid;
  String get _rosterPath =>
      schoolUid != null ? 'school/devices' : 'teachers/$teacherUid/devices';

  /// Nome exibido no popup da extensão. Mutável: renomear em Ajustes vale
  /// para os PRÓXIMOS pareamentos (o bind existente não é reescrito).
  String teacherName;

  final FirebaseDatabase _db;

  final SessionRegistry registry = SessionRegistry();

  /// deviceId do "PC do professor": fora de TODOS os broadcasts (abrir na
  /// turma, fechar site/tudo, encerrar aula, regras, wallpaper). Comandos
  /// individuais (sendCommand) continuam valendo — é assim que o telão recebe
  /// open_url/show_message. Setado pelo controller.
  String? pcProfessorId;

  /// Chamado ao (re)parear um PC — devolve os comandos de estado vigentes
  /// PARA AQUELE PC (set_rules sempre — pode variar por liberações da aula;
  /// set_wallpaper se houver). Injetado pelo controller.
  List<Map<String, dynamic>> Function(String deviceId)? comandosDeEstado;

  /// Chamado quando chega uma foto da câmera (capture_camera) já decifrada.
  /// [tipo] = `camera_snapshot` ou `screen_snapshot` (§3 do protocolo): um
  /// pedido de câmera não pode ser resolvido por uma captura de tela.
  void Function(String deviceId, String tipo, Uint8List jpeg)? onSnapshot;

  /// O roster foi negado pelas rules (e-mail tirado da escola com o app
  /// aberto). Injetado pelo controller.
  void Function()? onAcessoNegado;

  /// Ack decifrado e aceito pelo guard (de qualquer remetente: o controller
  /// só se importa com os ids que emitiu). Injetado pelo controller.
  void Function(String deviceId, Ack ack)? onAck;

  /// Destino do up/ de um PC (reserva de aula). Sem isto: mostra e notifica.
  DestinoUp Function(String deviceId)? destinoDoUp;

  /// Item novo do up/, decifrado, validado e deduplicado. [ms] = hora do
  /// servidor tirada do push id.
  void Function(String deviceId, UpMessage msg, int ms, DestinoUp destino)? onUp;

  /// O item [mid] saiu do up/ (outro aparelho agiu, o PC podou).
  void Function(String deviceId, String mid)? onUpRemovido;

  /// O PC passou do limite de mensagens e ficou silenciado por 10 min.
  void Function(String deviceId)? onUpSilenciado;

  /// state/lock ou state/exam mudou (já decifrado em PcSession.trava/.prova).
  void Function(String deviceId)? onEstadoTurma;

  /// Ids de comando emitidos por ESTE processo: só os acks deles são apagados.
  final IdsEmitidos idsEmitidos = IdsEmitidos();

  /// Teto, silêncio, idade e dedup do up/.
  final UpRouter upRouter = UpRouter();

  // Itens do up/ de PC reservado por outro: guardados sem ler, para o caso de
  // o PC ficar livre (ou meu) depois.
  final Map<String, Map<String, String>> _upIgnorados = {};

  // Processamento em série por PC e canal: o guard (sid,seq) exige ordem, e
  // decifrar é assíncrono.
  final Map<String, Future<void>> _filas = {};
  Future<void> _emSerie(String chave, Future<void> Function() tarefa) {
    final anterior = _filas[chave] ?? Future<void>.value();
    final proxima = anterior.then((_) => tarefa()).catchError((Object e) {
      debugPrint('[CdA] $chave: $e');
    });
    _filas[chave] = proxima;
    return proxima;
  }

  final Map<String, StreamSubscription<DatabaseEvent>> _thumbSubs = {};

  // Época de sessão (anti-replay): amostrada 1x por vida do processo.
  // Multi-remetente (workspace): sid NOVO por mensagem, no relógio do
  // SERVIDOR — o guard do PC aceita sid crescente, e o relógio do servidor é
  // comum a todos os celulares (2 professores alternando comandos no mesmo
  // PC não se envenenam; sid fixo por processo derrubava o de sid menor).
  // Replay continua rejeitado: sid <= último, ou igual com seq não-maior.
  int _ultimoSidEnviado = 0;
  int _proximoSid() {
    final t = nowServer().millisecondsSinceEpoch;
    _ultimoSidEnviado = t > _ultimoSidEnviado ? t : _ultimoSidEnviado + 1;
    return _ultimoSidEnviado;
  }

  final RelogioDoServidor _relogio = RelogioDoServidor();
  StreamSubscription<DatabaseEvent>? _offsetSub;
  StreamSubscription<DatabaseEvent>? _conexaoSub;
  StreamSubscription<DatabaseEvent>? _rosterSub;
  final Map<String, List<StreamSubscription<DatabaseEvent>>> _deviceSubs = {};
  final Map<String, bool> _primeiroReport = {};
  bool _rosterRecebido = false;

  /// PC ainda a caminho: roster não chegou ou a sessão está sendo
  /// rehidratada (a tela mostra "Carregando…" em vez de "desconectado").
  bool aguardandoPc(String deviceId) =>
      !_rosterRecebido ||
      (_deviceSubs.containsKey(deviceId) && registry.byId(deviceId) == null);

  /// Agora na base de tempo do SERVIDOR (p/ comparar com presence.lastSeen).
  DateTime nowServer() => _relogio.agora();

  /// O SDK está falando com o servidor (.info/connected)? Sem conexão, uma
  /// escrita fica na fila do SDK e o `await` não volta: as ações novas
  /// avisam "Sem conexão…" em vez de esperar para sempre.
  bool conectado = false;

  /// Conclui quando [nowServer] já usa o offset real do servidor.
  Future<void> get relogioPronto => _relogio.pronto;

  DatabaseReference _dev(String deviceId) => _db.ref('devices/$deviceId');

  Future<void> start() async {
    _offsetSub = _db
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((e) => _relogio.aoReceberOffset(e.snapshot.value));
    _conexaoSub = _db.ref('.info/connected').onValue.listen((e) {
      conectado = e.snapshot.value == true;
      _relogio.aoMudarConexao(e.snapshot.value);
    });
    // Roster: sincroniza o conjunto de PCs pareados (da escola, no workspace).
    _rosterSub = _db.ref(_rosterPath).onValue.listen(
      (e) {
        final ids = <String>{};
        final v = e.snapshot.value;
        if (v is Map) {
          for (final k in v.keys) {
            ids.add(k.toString());
          }
        }
        for (final id in ids) {
          if (!_deviceSubs.containsKey(id)) _attach(id);
        }
        for (final id in _deviceSubs.keys.toList()) {
          if (!ids.contains(id)) _detach(id, removerSessao: true);
        }
        if (!_rosterRecebido) {
          _rosterRecebido = true;
          registry.onChange?.call();
        }
      },
      onError: (Object e) {
        debugPrint('[CdA] roster: $e');
        if (e is FirebaseException && e.code == 'permission-denied') {
          onAcessoNegado?.call();
        }
      },
    );
  }

  Future<void> stop() async {
    await _offsetSub?.cancel();
    await _conexaoSub?.cancel();
    await _rosterSub?.cancel();
    for (final id in _deviceSubs.keys.toList()) {
      _detach(id);
    }
    for (final id in _thumbSubs.keys.toList()) {
      cancelarThumb(id);
    }
  }

  // ---- Pareamento -----------------------------------------------------------------

  /// Passo do professor no fluxo do QR: grava o bind (as rules validam token +
  /// TOFU), o roster e o estado vigente. Lança [FirebaseException]
  /// (permission-denied) se o QR expirou ou o PC pertence a outro professor.
  Future<void> pairDevice(QrPairPayload qr, {int? numero}) async {
    final sessionKey = await teacher.deriveSessionKey(pubFromB64url(qr.pub));
    await _dev(qr.deviceId).child('bind').set({
      'teacherUid': _donoUid,
      'teacherPub': pubToB64url(teacher.publicBytes),
      'teacherName': teacherName,
      'token': qr.token,
      'ts': ServerValue.timestamp,
      // Número da unidade (menor livre); a extensão exibe "Unidade N".
      if (numero != null) 'numero': numero,
    });
    await _db.ref('$_rosterPath/${qr.deviceId}').set(true);
    if (schoolUid != null) {
      // Roster pessoal em paralelo: rollback p/ app antigo continua vendo.
      await _db.ref('teachers/$teacherUid/devices/${qr.deviceId}').set(true);
    }

    final label = numero != null ? 'Unidade $numero' : qr.label;
    registry.bind(deviceId: qr.deviceId, label: label, sessionKey: sessionKey);
    if (!_deviceSubs.containsKey(qr.deviceId)) _attach(qr.deviceId);

    // Estado vigente (regras/wallpaper) — o PC atrasado lê state/* ao conectar.
    for (final cmd in comandosDeEstado?.call(qr.deviceId) ?? const []) {
      await setStateOne(qr.deviceId, cmd);
    }
  }

  /// "Esquecer PC": desfaz o vínculo no banco; a extensão detecta e volta ao QR.
  Future<void> forgetDevice(String deviceId) async {
    _detach(deviceId, removerSessao: true);
    await _dev(deviceId).child('bind').remove();
    await _removerDosRosters(deviceId);
  }

  Future<void> _removerDosRosters(String deviceId) async {
    await _db.ref('$_rosterPath/$deviceId').remove();
    if (schoolUid != null) {
      await _db
          .ref('teachers/$teacherUid/devices/$deviceId')
          .remove()
          .catchError((_) {});
    }
  }

  // ---- Listeners por PC --------------------------------------------------------------

  Future<void> _attach(String deviceId) async {
    _deviceSubs[deviceId] = []; // reserva antes dos awaits (evita attach duplo)
    _primeiroReport[deviceId] = true;

    // Sessão pode não existir ainda (app reaberto): rehidrata do meta/.
    if (registry.byId(deviceId) == null) {
      try {
        final meta = (await _dev(deviceId).child('meta').get()).value;
        if (meta is! Map) return _detach(deviceId);
        final pub = meta['pub'];
        if (pub is! String) return _detach(deviceId);
        final sessionKey = await teacher.deriveSessionKey(pubFromB64url(pub));
        registry.bind(
          deviceId: deviceId,
          label: (meta['label'] as String?) ?? 'Chromebook',
          sessionKey: sessionKey,
        );
      } catch (e) {
        debugPrint('[CdA] rehidratação de $deviceId falhou: $e');
        return _detach(deviceId);
      }
    }

    final subs = _deviceSubs[deviceId];
    if (subs == null) return; // detach durante os awaits

    subs.addAll([
      _dev(deviceId).child('presence/lastSeen').onValue.listen((e) {
        final ms = (e.snapshot.value as num?)?.toInt();
        if (ms != null) registry.touchServerTs(deviceId, ms);
      }),
      _dev(deviceId).child('report').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is Map) _onReport(deviceId, v);
      }),
      _dev(deviceId).child('snapshot').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is Map) _onSnapshot(deviceId, v);
      }),
      _dev(deviceId).child('ack').onChildAdded.listen((e) {
        final env = e.snapshot.value;
        final key = e.snapshot.key!;
        if (env is String) _emSerie('$deviceId|ack', () => _onAck(deviceId, key, env));
      }),
      _dev(deviceId).child('up').onChildAdded.listen((e) {
        final env = e.snapshot.value;
        final key = e.snapshot.key!;
        _emSerie('$deviceId|up', () => _onUp(deviceId, key, env));
      }),
      _dev(deviceId).child('up').onChildRemoved.listen((e) {
        final key = e.snapshot.key!;
        _emSerie('$deviceId|up', () async => _onUpRemovido(deviceId, key));
      }),
      _dev(deviceId).child('state/lock').onValue.listen((e) {
        final v = e.snapshot.value;
        _emSerie('$deviceId|lock', () => _onEstado(deviceId, 'lock', v));
      }),
      _dev(deviceId).child('state/exam').onValue.listen((e) {
        final v = e.snapshot.value;
        _emSerie('$deviceId|exam', () => _onEstado(deviceId, 'exam', v));
      }),
      _dev(deviceId).child('bind').onValue.listen((e) {
        // Bind sumiu = aluno desvinculou pelo popup: limpa roster e sessão.
        if (e.snapshot.value == null) {
          _detach(deviceId, removerSessao: true);
          _removerDosRosters(deviceId);
        }
      }),
      _dev(deviceId).child('meta/label').onValue.listen((e) {
        final label = e.snapshot.value;
        final s = registry.byId(deviceId);
        if (label is String && label.isNotEmpty && s != null && s.label != label) {
          s.label = label;
          registry.onChange?.call();
        }
      }),
      _dev(deviceId).child('meta/ext').onValue.listen((e) {
        final v = e.snapshot.value;
        final s = registry.byId(deviceId);
        if (s != null && v is String && s.versaoExt != v) {
          s.versaoExt = v;
          registry.onChange?.call();
        }
      }),
      _dev(deviceId).child('meta/os').onValue.listen((e) {
        final v = e.snapshot.value;
        final s = registry.byId(deviceId);
        if (s != null && v is String && s.versaoOs != v) {
          s.versaoOs = v;
          registry.onChange?.call();
        }
      }),
    ]);
  }

  void _detach(String deviceId, {bool removerSessao = false}) {
    final subs = _deviceSubs.remove(deviceId);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _primeiroReport.remove(deviceId);
    cancelarThumb(deviceId);
    upRouter.limparPc(deviceId);
    _upIgnorados.remove(deviceId);
    if (removerSessao) registry.remove(deviceId);
  }

  Future<void> _onReport(String deviceId, Map<dynamic, dynamic> node) async {
    final s = registry.byId(deviceId);
    final env = node['env'];
    if (s == null || env is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = await s.crypto.open(env);
    } catch (_) {
      return; // ilegível (raça de re-pareamento) — ignora
    }
    // 1ª leitura após abrir o app pode ser antiga (repousa no banco): aceita
    // sem janela de ts; ao vivo vale ±120s. sid/seq valem sempre.
    final primeira = _primeiroReport[deviceId] ?? true;
    _primeiroReport[deviceId] = false;
    final agora = DateTime.now().millisecondsSinceEpoch;
    final ok = s.reportGuard.accept(
      sid: (msg['sid'] as num?)?.toInt() ?? 0,
      seq: (msg['seq'] as num?)?.toInt() ?? 0,
      ts: primeira ? agora : (msg['ts'] as num?)?.toInt() ?? 0,
      nowMs: agora,
    );
    if (!ok) return;
    final report = TabReport.fromMap(msg);
    if (report == null) return;
    final serverTs = (node['ts'] as num?)?.toInt();
    registry.applyReport(
      deviceId,
      report,
      reportAt: serverTs != null ? DateTime.fromMillisecondsSinceEpoch(serverTs) : null,
    );
  }

  Future<void> _onSnapshot(String deviceId, Map<dynamic, dynamic> node) async {
    final s = registry.byId(deviceId);
    final env = node['env'];
    if (s == null || env is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = await s.crypto.open(env);
    } catch (_) {
      return; // ilegível (raça de re-pareamento) — ignora
    }
    final tipo = msg['type'];
    if (tipo != MessageType.cameraSnapshot && tipo != MessageType.screenSnapshot) {
      return;
    }
    final b64 = msg['jpegB64'];
    if (b64 is! String || b64.isEmpty) return;
    try {
      onSnapshot?.call(deviceId, tipo as String, base64Decode(b64));
    } catch (_) {
      // base64 inválido — ignora
    }
  }

  // Cliente novo só apaga ack de id que ELE emitiu: os de outro professor (ou
  // de antes de reiniciar o app) ficam para quem os emitiu, e o PC poda o
  // resto (≤ 20). O PC também repete os últimos acks em `aplicado.acks`.
  Future<void> _onAck(String deviceId, String pushId, String env) async {
    final s = registry.byId(deviceId);
    if (s == null) return;
    Ack? ack;
    try {
      final msg = await s.crypto.open(env);
      ack = Ack.fromMap(msg);
      final agora = DateTime.now().millisecondsSinceEpoch;
      final ok = s.ackGuard.accept(
        sid: (msg['sid'] as num?)?.toInt() ?? 0,
        seq: (msg['seq'] as num?)?.toInt() ?? 0,
        ts: (msg['ts'] as num?)?.toInt() ?? agora,
        nowMs: agora,
      );
      if (ok && ack != null) {
        if (!ack.ok) {
          debugPrint('[CdA] ack com erro de $deviceId: ${ack.error} (${ack.id})');
        }
        onAck?.call(deviceId, ack);
      }
    } catch (_) {
      return; // ilegível (outra chave): não sabemos de quem é — o PC poda
    }
    if (ack != null && idsEmitidos.contem(ack.id)) {
      await _dev(deviceId).child('ack/$pushId').remove().catchError((_) {});
    }
  }

  // ---- Canal up/ (aluno -> professor) ---------------------------------------
  // Ordem (SPEC-turma §2.7): destino pela reserva de aula (ignorar = nem
  // decifra, nem apaga) → idade/teto/silêncio → decifra + upGuard → valida
  // caps e site → dedup por (deviceId, mid) → controller.

  DestinoUp _destino(String deviceId) =>
      destinoDoUp?.call(deviceId) ?? DestinoUp.mostrarENotificar;

  Future<void> _onUp(String deviceId, String key, Object? env) async {
    final destino = _destino(deviceId);
    if (destino == DestinoUp.ignorar) {
      if (env is String) (_upIgnorados[deviceId] ??= {})[key] = env;
      return;
    }
    final agora = nowServer().millisecondsSinceEpoch;
    final chegada = upRouter.aoChegar(deviceId, key, agora);
    for (final velha in chegada.apagar) {
      unawaited(apagarUp(deviceId, velha).catchError((_) {}));
    }
    if (chegada.silenciou) onUpSilenciado?.call(deviceId);
    if (!chegada.ler || env is! String) return;
    if (env.length >= kUpMaxEnvelope) return; // as rules já barram; defensivo
    final s = registry.byId(deviceId);
    if (s == null) return;
    final Map<String, dynamic> msg;
    try {
      msg = await s.crypto.open(env);
    } catch (_) {
      return; // outra chave (re-pareamento): o PC poda em 2 h
    }
    final up = UpMessage.fromMap(msg);
    if (up == null) return; // fora do protocolo: descarta calado
    final ok = s.upGuard.accept(sid: up.sid, seq: up.seq, ts: up.ts, nowMs: agora);
    if (!ok) return;
    if (!upRouter.aoLer(deviceId, key, up)) return; // repetido (mesmo mid)
    onUp?.call(deviceId, up, pushIdMs(key) ?? agora, destino);
  }

  void _onUpRemovido(String deviceId, String key) {
    _upIgnorados[deviceId]?.remove(key);
    final mid = upRouter.aoRemover(deviceId, key);
    if (mid != null) onUpRemovido?.call(deviceId, mid);
  }

  /// A reserva de aula mudou: itens guardados de PC que deixou de ser de
  /// outro professor passam pelo caminho normal.
  void reavaliarUpIgnorados() {
    for (final deviceId in _upIgnorados.keys.toList()) {
      if (_destino(deviceId) == DestinoUp.ignorar) continue;
      final itens = _upIgnorados.remove(deviceId) ?? const {};
      final chaves = itens.keys.toList()..sort();
      for (final k in chaves) {
        _emSerie('$deviceId|up', () => _onUp(deviceId, k, itens[k]));
      }
    }
  }

  /// Apaga um item do up/ (só filhos: as rules não deixam o professor apagar
  /// o nó inteiro). Lança em erro (o controller mostra o texto de §1.3).
  Future<void> apagarUp(String deviceId, String key) =>
      _dev(deviceId).child('up/$key').remove();

  /// Apaga todas as chaves do item [mid] (o pedido/mão que o professor
  /// resolveu, com as repetições).
  Future<void> apagarUpDoMid(String deviceId, String mid) async {
    final chaves = upRouter.chavesDe(deviceId, mid);
    if (chaves.isEmpty) return;
    await _dev(deviceId).child('up').update({for (final k in chaves) k: null});
  }

  /// "Encerrar aula": apaga todo o up/ de um PC, filho a filho.
  Future<void> apagarTodoUp(String deviceId) async {
    final snap = await _dev(deviceId).child('up').get();
    final chaves = [for (final c in snap.children) if (c.key != null) c.key!];
    if (chaves.isEmpty) return;
    await _dev(deviceId).child('up').update({for (final k in chaves) k: null});
  }

  // ---- state/lock e state/exam (o que o PC deve aplicar) ----------------------

  Future<void> _onEstado(String deviceId, String no, Object? v) async {
    final s = registry.byId(deviceId);
    if (s == null) return;
    Map<String, dynamic>? cmd;
    if (v is String) {
      try {
        cmd = await s.crypto.open(v);
      } catch (_) {
        cmd = null; // chave nova (app reinstalado): o PC destrava pelo prazo
      }
    }
    if (no == 'lock') {
      s.trava = cmd == null ? null : EstadoTrava.fromCommand(cmd);
    } else {
      s.prova = cmd == null ? null : EstadoProva.fromCommand(cmd);
    }
    onEstadoTurma?.call(deviceId);
    registry.onChange?.call();
  }

  // ---- Miniaturas da grade (/thumbs/{id}, fora de /devices) -------------------

  /// Assina a miniatura do PC (só enquanto a grade está aberta).
  void assinarThumb(String deviceId) {
    if (_thumbSubs.containsKey(deviceId)) return;
    _thumbSubs[deviceId] = _db.ref('thumbs/$deviceId').onValue.listen(
      (e) {
        final v = e.snapshot.value;
        _emSerie('$deviceId|thumb', () => _onThumb(deviceId, v));
      },
      onError: (Object e) => debugPrint('[CdA] thumbs/$deviceId: $e'),
    );
  }

  void cancelarThumb(String deviceId) {
    _thumbSubs.remove(deviceId)?.cancel();
    registry.byId(deviceId)?.thumb = null;
  }

  Future<void> _onThumb(String deviceId, Object? v) async {
    final s = registry.byId(deviceId);
    if (s == null || !_thumbSubs.containsKey(deviceId)) return;
    Miniatura? m;
    if (v is Map) {
      final env = v['env'];
      final ts = v['ts'];
      if (env is String && env.length < kThumbCapLido && ts is num) {
        try {
          m = Miniatura.fromMap(await s.crypto.open(env), ts: ts.toInt());
        } catch (_) {
          m = null;
        }
      }
    }
    s.thumb = m;
    registry.onChange?.call();
  }

  /// Apaga a miniatura do PC (ao fechar a grade). Lança em erro.
  Future<void> apagarThumb(String deviceId) =>
      _db.ref('thumbs/$deviceId').remove();

  /// Apaga state/monitor (o PC para de capturar na hora). Lança em erro.
  Future<void> apagarMonitor(String deviceId) =>
      _dev(deviceId).child('state/monitor').remove();

  // ---- Saída (comandos) -----------------------------------------------------------

  Future<String> _sealFor(PcSession s, Map<String, dynamic> cmd) {
    return s.crypto.seal({
      'sid': _proximoSid(),
      'seq': 1,
      'ts': nowServer().millisecondsSinceEpoch,
      ...cmd,
    });
  }

  /// Enfileira um comando one-shot (open_url, close_tabs) para um PC.
  /// Devolve o id do comando (o do ack), ou null se o PC não está na sessão.
  Future<String?> sendCommand(String deviceId, Map<String, dynamic> cmd) async {
    final s = registry.byId(deviceId);
    if (s == null) return null;
    final id = cmd['id'];
    if (id is String) idsEmitidos.registrar(id);
    final env = await _sealFor(s, cmd);
    await _dev(deviceId).child('cmd').push().set(env);
    return id is String ? id : null;
  }

  /// Turma toda (envelopes diferem: cada sessão tem sua chave).
  /// O PC do professor fica de fora — comandos pra ele são individuais.
  Future<void> sendToAll(Map<String, dynamic> cmd) async {
    for (final s in registry.all) {
      if (s.deviceId == pcProfessorId) continue;
      await sendCommand(s.deviceId, cmd);
    }
  }

  /// Comando de estado: sobrescreve state/rules|wallpaper|classview|unit|
  /// lock|exam|monitor. Tipo que não é de estado lança [ArgumentError].
  Future<void> setStateOne(String deviceId, Map<String, dynamic> cmd) async {
    final kind = noDeEstado(cmd['type']);
    final s = registry.byId(deviceId);
    if (s == null) return;
    final env = await _sealFor(s, cmd);
    await _dev(deviceId).child('state/$kind').set(env);
  }

  /// "Escreve null" num nó de estado (ex.: PC deixou de ser o telão).
  /// Não exige sessão no registry: o alvo pode já ter sido esquecido.
  Future<void> clearState(String deviceId, String kind) async {
    await _dev(deviceId).child('state/$kind').remove();
  }

  /// Publica o blob do papel de parede (1x, compartilhado pela turma).
  /// O comando set_wallpaper (só o hash) vai por setStateAll.
  Future<void> publishWallpaper(Uint8List bytes, String hash) async {
    await _db.ref('wallpapers/$_donoUid').set({
      'hash': hash,
      'jpeg': base64Encode(bytes),
      'ts': ServerValue.timestamp,
    });
  }

  /// Página inicial dos alunos: única escrita em claro do app. Não é comando de
  /// PC — é a configuração da escola, que a página escolacelita.com/home lê sem
  /// login. As regras só aceitam esta escrita da conta Google da escola.
  /// `update` (não `set`): preserva chaves que outros clientes gravem no nó.
  Future<void> publicarPaginaInicial(Map<String, dynamic> config) async {
    await _db.ref('home/escola').update({
      'rev': DateTime.now().millisecondsSinceEpoch,
      'cfg': jsonEncode(config),
    });
  }

  Future<void> setStateAll(Map<String, dynamic> cmd) async {
    for (final s in registry.all) {
      if (s.deviceId == pcProfessorId) continue;
      await setStateOne(s.deviceId, cmd);
    }
  }
}
