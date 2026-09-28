// Arquivo de 15 dias por PC do Celita OS (/archive/{deviceId}): histórico de
// navegação em lotes cifrados ("nav-v1") e o índice das fotos da câmera, que
// ficam no Cloud Storage ("foto-v1"). Tudo com a chave de sessão do PC.
// Ver docs/protocolo.md.
//
// O núcleo (dia, parse dos lotes, escolha da foto) é puro e testável sem
// Firebase; só ArchiveStore toca o RTDB/Storage.

import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../secure/crypto.dart';

// São Paulo é UTC−3 fixo desde 2019: o dia dos nós não depende do fuso do
// celular nem do horário de verão.
const int _kOffsetEscolaMs = 3 * 60 * 60 * 1000;
const int _kDiaMs = 24 * 60 * 60 * 1000;

/// Quantos dias o arquivo guarda (hoje + 14 anteriores).
const int kArchiveDays = 15;

/// Teto de download de uma foto (o agente manda < 400 KiB).
const int kMaxPhotoBytes = 1024 * 1024;

/// Dia (AAAA-MM-DD) de um instante, em UTC−3.
String dayOf(int tsMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs - _kOffsetEscolaMs, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// Início (ms) de um dia AAAA-MM-DD em UTC−3.
int dayStartMs(String day) =>
    DateTime.parse('${day}T00:00:00Z').millisecondsSinceEpoch + _kOffsetEscolaMs;

/// Os [count] dias até o de [nowMs], do mais novo para o mais velho.
List<String> recentDays(int nowMs, {int count = kArchiveDays}) =>
    [for (var k = 0; k < count; k++) dayOf(nowMs - k * _kDiaMs)];

/// Chave do índice de fotos: ms com 13 dígitos (ordena como texto).
String ts13(int ms) => ms.toString().padLeft(13, '0');

class ArchivedNavEvent {
  const ArchivedNavEvent({
    required this.ts,
    required this.url,
    required this.title,
    this.action,
    this.photoTs,
  });

  final int ts;
  final String url;
  final String title;

  /// 'bloqueado', 'alerta' ou null.
  final String? action;

  /// ts13 da foto tirada por este evento (só se a captura deu certo).
  final int? photoTs;

  static ArchivedNavEvent? fromMap(Object? m) {
    if (m is! Map) return null;
    final ts = m['ts'];
    final url = m['url'];
    if (ts is! num || url is! String || url.isEmpty) return null;
    final title = m['title'];
    final action = m['acao'];
    final foto = m['foto'];
    return ArchivedNavEvent(
      ts: ts.toInt(),
      url: url,
      title: title is String ? title : '',
      action: action == 'bloqueado' || action == 'alerta' ? action as String : null,
      photoTs: foto is num ? foto.toInt() : null,
    );
  }
}

/// Uma entrada numa conta do PC (lotes com o mesmo login).
class ArchivedSession {
  ArchivedSession({required this.user, required this.login});

  final String user;
  final int login;
  final List<ArchivedNavEvent> events = [];
}

class ArchivedDay {
  const ArchivedDay({required this.sessions, required this.unreadable});

  /// Por hora de entrada; eventos por ts.
  final List<ArchivedSession> sessions;

  /// Lotes que não abriram com a chave deste PC ou com formato estranho.
  final int unreadable;

  bool get isEmpty => sessions.every((s) => s.events.isEmpty);
}

/// Decifra os lotes de um dia (`archive/{id}/nav/{dia}`), pula os ilegíveis,
/// agrupa por entrada na conta e ordena por hora.
Future<ArchivedDay> parseNavDay(Object? raw, SessionCrypto crypto) async {
  final sessions = <String, ArchivedSession>{};
  final seen = <String>{};
  var unreadable = 0;
  if (raw is Map) {
    for (final node in raw.values) {
      final env = node is Map ? node['env'] : null;
      if (env is! String) {
        unreadable++;
        continue;
      }
      Map<String, dynamic> obj;
      try {
        obj = await crypto.open(env);
      } catch (_) {
        unreadable++;
        continue;
      }
      final user = obj['user'];
      final login = obj['login'];
      final events = obj['events'];
      if (obj['v'] != 1 ||
          obj['type'] != 'archived_nav' ||
          user is! String ||
          login is! num ||
          events is! List) {
        unreadable++;
        continue;
      }
      final key = '${login.toInt()}|$user';
      final session =
          sessions[key] ??= ArchivedSession(user: user, login: login.toInt());
      for (final e in events) {
        final ev = ArchivedNavEvent.fromMap(e);
        // Reenvio de um lote após timeout chega duplicado.
        if (ev != null && seen.add('$key|${ev.ts}|${ev.url}')) {
          session.events.add(ev);
        }
      }
    }
  }
  final list = sessions.values.toList()
    ..sort((a, b) => a.login.compareTo(b.login));
  for (final s in list) {
    s.events.sort((a, b) => a.ts.compareTo(b.ts));
  }
  return ArchivedDay(sessions: list, unreadable: unreadable);
}

// ---- Fotos -------------------------------------------------------------------------

final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final RegExp _randomRe = RegExp(r'^[A-Za-z0-9_-]{22}$');
final RegExp _ts13Re = RegExp(r'^[0-9]{13}$');

/// Entrada do índice `archive/{id}/fotos/{dia}/{ts13} = {u, r}`.
class PhotoRef {
  const PhotoRef({
    required this.day,
    required this.ts,
    required this.uid,
    required this.random,
  });

  final String day;
  final int ts;
  final String uid;
  final String random;

  String get path => 'fotos/$uid/$day/${ts13(ts)}_$random.bin';

  /// Valida a entrada antes de montar um caminho do Storage com ela.
  static PhotoRef? parse(String day, Object? key, Object? value) {
    if (key is! String || !_ts13Re.hasMatch(key) || value is! Map) return null;
    final u = value['u'];
    final r = value['r'];
    if (u is! String || !_uidRe.hasMatch(u)) return null;
    if (r is! String || !_randomRe.hasMatch(r)) return null;
    return PhotoRef(day: day, ts: int.parse(key), uid: u, random: r);
  }
}

/// Consultas por chave no índice de fotos de um PC (abstraídas para teste).
abstract class PhotoIndex {
  /// A entrada exata `{dia}/{ts13}`.
  Future<PhotoRef?> exact(String day, int ts);

  /// A última com `from <= ts <= to`.
  Future<PhotoRef?> lastBetween(String day, int from, int to);

  /// A primeira com `ts >= from`.
  Future<PhotoRef?> firstFrom(String day, int from);
}

enum PhotoFailure { deleted, download, unreadable }

class PhotoException implements Exception {
  const PhotoException(this.failure);

  final PhotoFailure failure;

  @override
  String toString() => 'PhotoException($failure)';
}

class ChosenPhoto {
  const ChosenPhoto(this.ref, this.photo);

  final PhotoRef ref;
  final ArchivedPhoto photo;
}

/// Foto que mostra quem estava no PC na hora de [event] (null = nenhuma).
/// 1) a foto marcada no evento; 2) a mais próxima antes (desde a entrada na
/// conta) ou depois; a de depois só vale se for da mesma entrada na conta.
Future<ChosenPhoto?> pickPhoto({
  required String day,
  required ArchivedSession session,
  required ArchivedNavEvent event,
  required PhotoIndex index,
  required Future<ArchivedPhoto> Function(PhotoRef ref) open,
}) async {
  final marked = event.photoTs;
  if (marked != null) {
    // A foto marcada pode ser do dia anterior (reaproveitada perto da meia-noite).
    final ref = await index.exact(dayOf(marked), marked);
    if (ref != null) return ChosenPhoto(ref, await open(ref));
  }
  final from = max(session.login, dayStartMs(day));
  final before =
      from <= event.ts ? await index.lastBetween(day, from, event.ts) : null;
  final after = await index.firstFrom(day, event.ts);
  if (after != null &&
      (before == null || after.ts - event.ts < event.ts - before.ts)) {
    try {
      final photo = await open(after);
      if (photo.login == session.login && photo.user == session.user) {
        return ChosenPhoto(after, photo);
      }
    } catch (_) {
      if (before == null) rethrow;
    }
  }
  if (before == null) return null;
  return ChosenPhoto(before, await open(before));
}

/// Caminhos de uma poda de reserva: dias de hoje−45 a hoje−15, para cada PC.
Map<String, Object?> prunePaths(Iterable<String> deviceIds, int nowMs) {
  final paths = <String, Object?>{};
  for (final id in deviceIds) {
    for (var k = kArchiveDays; k <= 45; k++) {
      final d = dayOf(nowMs - k * _kDiaMs);
      paths['archive/$id/nav/$d'] = null;
      paths['archive/$id/fotos/$d'] = null;
    }
  }
  return paths;
}

class ArchiveStore implements PhotoIndex {
  ArchiveStore({
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

  DatabaseReference _photos(String day) =>
      _db.ref('archive/$deviceId/fotos/$day');

  /// Lança em erro de leitura (rede/permissão).
  Future<ArchivedDay> readDay(String day) async {
    final snap = await _db.ref('archive/$deviceId/nav/$day').get();
    return parseNavDay(snap.value, crypto);
  }

  PhotoRef? _first(String day, DataSnapshot snap) {
    for (final c in snap.children) {
      return PhotoRef.parse(day, c.key, c.value);
    }
    return null;
  }

  @override
  Future<PhotoRef?> exact(String day, int ts) async {
    final snap = await _photos(day).child(ts13(ts)).get();
    return PhotoRef.parse(day, snap.key, snap.value);
  }

  @override
  Future<PhotoRef?> lastBetween(String day, int from, int to) async {
    final snap = await _photos(day)
        .orderByKey()
        .startAt(ts13(from))
        .endAt(ts13(to))
        .limitToLast(1)
        .get();
    return _first(day, snap);
  }

  @override
  Future<PhotoRef?> firstFrom(String day, int from) async {
    final snap = await _photos(day)
        .orderByKey()
        .startAt(ts13(from))
        .limitToFirst(1)
        .get();
    return _first(day, snap);
  }

  /// Baixa e abre uma foto. Lança [PhotoException].
  Future<ArchivedPhoto> download(PhotoRef ref) async {
    final List<int>? data;
    try {
      data = await _storage.ref(ref.path).getData(kMaxPhotoBytes);
    } on FirebaseException catch (e) {
      throw PhotoException(
        e.code == 'object-not-found' ? PhotoFailure.deleted : PhotoFailure.download,
      );
    } catch (_) {
      throw const PhotoException(PhotoFailure.download);
    }
    if (data == null) throw const PhotoException(PhotoFailure.download);
    try {
      return await crypto.openPhoto(data, ts: ref.ts);
    } catch (_) {
      throw const PhotoException(PhotoFailure.unreadable);
    }
  }

  Future<ChosenPhoto?> photoFor(
    String day,
    ArchivedSession session,
    ArchivedNavEvent event,
  ) =>
      pickPhoto(
        day: day,
        session: session,
        event: event,
        index: this,
        open: download,
      );

  /// Poda de reserva do arquivo de vários PCs (a do agente é a principal).
  static Future<void> prune(
    Iterable<String> deviceIds,
    int nowMs, {
    FirebaseDatabase? database,
  }) async {
    final db = database ?? FirebaseDatabase.instance;
    for (final id in deviceIds) {
      await db.ref().update(prunePaths([id], nowMs));
    }
  }
}
