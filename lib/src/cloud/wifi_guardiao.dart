// Celular guardião do Wi-Fi da escola (docs/protocolo.md §9): com o app
// aberto, entrega a chave da frota a cada PC da escola que publica a pública,
// sem depender de outro PC ligado. Vê a chave, mas nunca lê redes nem chaves.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../secure/keypair.dart';
import '../secure/wifi_crypto.dart';

class WifiGuardiao {
  WifiGuardiao({
    required this.uid,
    required this.chave,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final String uid;

  /// Par só deste celular (KeyStore.loadOrCreateGuardiao), fora de backup.
  final DeviceKeyPair chave;
  final FirebaseDatabase _db;

  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  final Map<String, Object?> _nos = {};
  List<int>? _frota; // a chave da frota só existe aqui, na memória
  // Muda com o kcv, com o próprio nó e no stop(): a chave aberta antes não
  // sela mais nada.
  int _geracao = 0;
  // O nó já foi deste aparelho: outra pública ali depois é outro aparelho da
  // mesma conta Google, aberto depois, e este cede o lugar em vez de brigar.
  bool _assumi = false;
  Timer? _espera;
  bool _rodando = false;
  bool _denovo = false;

  DatabaseReference get _wifi => _db.ref('school/wifi');

  void start() {
    final nos = <String, Query>{
      'kcv': _wifi.child('meta/kcv'),
      'meu': _wifi.child('guardioes/$uid'),
      'pubs': _wifi.child('pubs'),
      'entregas': _wifi.child('entregas'),
      'roster': _db.ref('school/devices'),
    };
    nos.forEach(_ouvir);
  }

  Future<void> stop() async {
    _esquecer();
    _espera?.cancel();
    _nos.clear();
    final subs = [..._subs];
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  void _ouvir(String nome, Query no) {
    _subs.add(
      no.onValue.listen(
        (e) {
          if (_subs.isEmpty) return;
          _nos[nome] = e.snapshot.value;
          if (nome == 'kcv' || nome == 'meu') _esquecer();
          _agendar();
        },
        onError: (Object e) {
          if (_subs.isEmpty) return;
          // Rules antigas ou e-mail tirado da escola: o guardião só para.
          debugPrint('[CdA] guardião do Wi-Fi parou: $e');
          unawaited(stop());
        },
      ),
    );
  }

  void _esquecer() {
    _frota = null;
    _geracao++;
  }

  void _agendar() {
    _espera?.cancel();
    _espera = Timer(const Duration(seconds: 2), () => unawaited(_rodar()));
  }

  Future<void> _rodar() async {
    if (_rodando) {
      _denovo = true;
      return;
    }
    _rodando = true;
    try {
      do {
        _denovo = false;
        try {
          await _passo();
        } catch (e) {
          debugPrint('[CdA] guardião do Wi-Fi: $e');
        }
      } while (_denovo && _subs.isNotEmpty);
    } finally {
      _rodando = false;
    }
  }

  Future<void> _passo() async {
    if (_subs.isEmpty || _nos.length < _subs.length) return;
    final geracao = _geracao;
    final minha = pubToB64url(chave.publicBytes);
    final meu = _nos['meu'];
    if (meu is! Map || meu['pub'] != minha) {
      if (_assumi && meu is Map && meu['pub'] is String) {
        debugPrint('[CdA] guardião do Wi-Fi: outro aparelho desta conta assumiu');
        return stop();
      }
      // Cadastro, ou par novo neste celular: o set apaga a chave selada antes.
      _assumi = true;
      await _wifi
          .child('guardioes/$uid')
          .set({'pub': minha, 'ts': ServerValue.timestamp});
      return;
    }
    _assumi = true;
    final kcv = _nos['kcv'];
    final selada = meu['chave'];
    final pubs = _nos['pubs'];
    if (kcv is! String || selada is! Map || pubs is! Map) return;
    var frota = _frota;
    if (frota == null) {
      final pubDoPc = pubs[selada['de']];
      final env = selada['env'];
      frota = pubDoPc is String && env is String
          ? await abrirChaveDaFrota(
              guardiao: chave,
              pubDoPc: pubDoPc,
              env: env,
              kcv: kcv,
            )
          : null;
      if (geracao != _geracao) return;
      if (frota == null) {
        // Não abre ou não é a da escola: sai, e um PC sela de novo.
        await _wifi.child('guardioes/$uid/chave').remove();
        return;
      }
      _frota = frota;
    }
    final alvos = alvosDaEntrega(
      pubs: pubs,
      roster: _nos['roster'],
      entregas: _nos['entregas'],
      uid: uid,
      kcv: kcv,
    );
    for (final id in alvos) {
      try {
        final entrega = await selarEntrega(frota, pubs[id] as String);
        if (geracao != _geracao) return;
        await _wifi.child('entregas/$id/$uid').set(entrega);
      } catch (e) {
        // Pública torta ou PC que saiu da escola no meio: os outros seguem.
        debugPrint('[CdA] entrega do Wi-Fi para $id: $e');
      }
    }
  }
}

/// PCs que ainda não têm a entrega deste guardião com a chave de agora: no
/// roster e com a pública em pubs (só o agente do Celita publica; Chromebook
/// nunca). O PC não apaga entregas: a vaga de outra chave se refaz aqui.
List<String> alvosDaEntrega({
  required Object? pubs,
  required Object? roster,
  required Object? entregas,
  required String uid,
  required String kcv,
}) {
  if (pubs is! Map || roster is! Map) return const [];
  final feitas = entregas is Map ? entregas : const {};
  bool entregue(Object? id) {
    final doPc = feitas[id];
    final minha = doPc is Map ? doPc[uid] : null;
    return minha is Map && minha['kcv'] == kcv;
  }

  return [
    for (final e in pubs.entries)
      if (e.value is String && roster[e.key] == true && !entregue(e.key))
        '${e.key}',
  ]..sort();
}
