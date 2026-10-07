// Fotos e vídeos da Câmera de um PC do Celita OS: índice cifrado em
// /midia/{deviceId} e envio sob pedido em partes cifradas (midia-v1) no
// Storage, com o progresso em /envios/{deviceId}/{mid}. Tudo com a chave de
// sessão do PC. Ver docs/protocolo.md ("Fotos e vídeos da Câmera").
//
// O núcleo (parse do índice e do envio, aad das partes, montagem do arquivo)
// é puro e testável sem Firebase; só MediaStore toca o RTDB/Storage.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../secure/crypto.dart';

/// Parte cifrada: 4 MiB de dados + nonce e tag.
const int kMidiaParteMax = 4 * 1024 * 1024 + 64;

final RegExp _midRe = RegExp(r'^[A-Za-z0-9_-]{16}$');
final RegExp _rRe = RegExp(r'^[A-Za-z0-9_-]{22}$');
final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

class MediaItem {
  const MediaItem({
    required this.mid,
    required this.video,
    required this.nome,
    required this.conta,
    required this.ts,
    required this.bytes,
    required this.guardado,
    this.expira,
    this.duracao,
    this.thumb,
  });

  final String mid;
  final bool video;
  final String nome;
  final String conta;
  final int ts;
  final int bytes;

  /// Saiu da pasta do aluno no logout: fica no PC até [expira].
  final bool guardado;
  final int? expira;

  /// Segundos (só vídeo).
  final double? duracao;
  final Uint8List? thumb;

  static MediaItem? fromMap(Object? m) {
    if (m is! Map || m['type'] != 'midia') return null;
    final mid = m['mid'];
    final tipo = m['tipo'];
    final nome = m['nome'];
    final conta = m['conta'];
    final ts = m['ts'];
    final bytes = m['bytes'];
    if (mid is! String || !_midRe.hasMatch(mid)) return null;
    if (tipo != 'foto' && tipo != 'video') return null;
    if (nome is! String || conta is! String || ts is! num || bytes is! num) return null;
    Uint8List? thumb;
    final t = m['thumb'];
    if (t is String && t.isNotEmpty) {
      try {
        thumb = base64Decode(t);
      } catch (_) {}
    }
    final expira = m['expira'];
    final duracao = m['duracao'];
    return MediaItem(
      mid: mid,
      video: tipo == 'video',
      nome: nome,
      conta: conta,
      ts: ts.toInt(),
      bytes: bytes.toInt(),
      guardado: m['guardado'] == true,
      expira: expira is num ? expira.toInt() : null,
      duracao: duracao is num ? duracao.toDouble() : null,
      thumb: thumb,
    );
  }
}

/// Estado de um envio em /envios/{deviceId}/{mid}, escrito pelo PC.
class EnvioMidia {
  const EnvioMidia({
    required this.uid,
    required this.r,
    required this.partes,
    required this.prontas,
    required this.bytes,
    this.erro,
  });

  final String uid;
  final String r;
  final int partes;
  final int prontas;
  final int bytes;
  final String? erro;

  static EnvioMidia? fromMap(Object? m) {
    if (m is! Map) return null;
    final u = m['u'];
    final r = m['r'];
    final partes = m['partes'];
    final prontas = m['prontas'];
    final bytes = m['bytes'];
    if (u is! String || !_uidRe.hasMatch(u) || r is! String || !_rRe.hasMatch(r)) return null;
    if (partes is! num || prontas is! num || bytes is! num || partes < 1) return null;
    final erro = m['erro'];
    return EnvioMidia(
      uid: u,
      r: r,
      partes: partes.toInt(),
      prontas: prontas.toInt().clamp(0, partes.toInt()),
      bytes: bytes.toInt(),
      erro: erro is String ? erro : null,
    );
  }

  String caminho(String mid, int n) => 'midia/$uid/$mid/${r}_$n.bin';
}

List<int> aadDaParte(String mid, String r, int n, int total) =>
    ascii.encode('midia-v1|$mid|$r|$n|$total');

/// Decifra o índice; entradas ilegíveis (outra chave, formato estranho) somem.
Future<List<MediaItem>> parseIndice(Object? raw, SessionCrypto crypto) async {
  final itens = <MediaItem>[];
  if (raw is Map) {
    for (final entry in raw.entries) {
      final env = entry.value is Map ? (entry.value as Map)['env'] : null;
      if (env is! String) continue;
      try {
        final item = MediaItem.fromMap(await crypto.open(env));
        if (item != null && item.mid == entry.key) itens.add(item);
      } catch (_) {}
    }
  }
  itens.sort((a, b) => b.ts.compareTo(a.ts));
  return itens;
}

class MidiaException implements Exception {
  const MidiaException(this.motivo);

  /// 'pc_falhou', 'sem_progresso', 'parte_ilegivel', 'download'.
  final String motivo;

  @override
  String toString() => 'MidiaException($motivo)';
}

class MediaStore {
  MediaStore({
    required this.deviceId,
    required this.crypto,
    FirebaseDatabase? database,
    FirebaseStorage? storage,
  })  : _db = database ?? FirebaseDatabase.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final String deviceId;
  final SessionCrypto crypto;
  final FirebaseDatabase _db;
  final FirebaseStorage _storage;

  DatabaseReference _envio(String mid) => _db.ref('envios/$deviceId/$mid');

  Stream<List<MediaItem>> watch() =>
      _db.ref('midia/$deviceId').onValue.asyncMap((e) => parseIndice(e.snapshot.value, crypto));

  /// Pede o envio (por [pedir], que manda o comando) e monta o arquivo em
  /// [destino] à medida que as partes chegam. Lança [MidiaException].
  Future<void> baixar(
    MediaItem item,
    File destino, {
    required Future<String?> Function() pedir,
    void Function(double fracao)? onProgress,
    Duration semProgresso = const Duration(seconds: 90),
  }) async {
    // Um envio velho no nó seria confundido com o novo.
    await _envio(item.mid).remove();
    final erroDoPedido = await pedir();
    if (erroDoPedido != null) throw MidiaException(erroDoPedido);
    final saida = await destino.open(mode: FileMode.write);
    final pronto = Completer<void>();
    EnvioMidia? envio;
    var proxima = 0;
    var ocupado = false;
    Timer? relogio;
    void armar() {
      relogio?.cancel();
      relogio = Timer(semProgresso, () {
        if (!pronto.isCompleted) pronto.completeError(const MidiaException('sem_progresso'));
      });
    }

    Future<void> puxar() async {
      if (ocupado || pronto.isCompleted) return;
      ocupado = true;
      try {
        final e = envio;
        while (e != null && proxima < e.prontas && !pronto.isCompleted) {
          final List<int>? blob;
          try {
            blob = await _storage.ref(e.caminho(item.mid, proxima)).getData(kMidiaParteMax);
          } catch (_) {
            throw const MidiaException('download');
          }
          if (blob == null) throw const MidiaException('download');
          final List<int> dados;
          try {
            dados = await crypto.openPart(blob, aadDaParte(item.mid, e.r, proxima, e.partes));
          } catch (_) {
            throw const MidiaException('parte_ilegivel');
          }
          await saida.writeFrom(dados);
          proxima++;
          onProgress?.call(proxima / e.partes);
          armar();
        }
        if (e != null && proxima == e.partes && !pronto.isCompleted) pronto.complete();
      } catch (erro) {
        if (!pronto.isCompleted) pronto.completeError(erro);
      } finally {
        ocupado = false;
      }
      // Parte que ficou pronta enquanto esta rodada baixava.
      final e = envio;
      if (e != null && proxima < e.prontas && !pronto.isCompleted) unawaited(puxar());
    }

    armar();
    final assinatura = _envio(item.mid).onValue.listen((evento) {
      final atual = EnvioMidia.fromMap(evento.snapshot.value);
      if (atual == null) return;
      if (envio != null && atual.r != envio!.r) return;
      if (atual.erro != null) {
        if (!pronto.isCompleted) pronto.completeError(const MidiaException('pc_falhou'));
        return;
      }
      envio = atual;
      unawaited(puxar());
    });
    try {
      await pronto.future;
    } finally {
      relogio?.cancel();
      await assinatura.cancel();
      await saida.close();
      final e = envio;
      if (e != null) unawaited(limpar(item.mid, e));
    }
  }

  /// As partes só existem para chegar ao celular: saem do Storage logo depois.
  Future<void> limpar(String mid, EnvioMidia envio) async {
    for (var n = 0; n < envio.partes; n++) {
      try {
        await _storage.ref(envio.caminho(mid, n)).delete();
      } catch (_) {}
    }
    try {
      await _envio(mid).remove();
    } catch (_) {}
  }
}
