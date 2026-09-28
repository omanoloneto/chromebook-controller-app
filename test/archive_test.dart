// Arquivo de 15 dias (spec 3.0–3.3): dia em UTC−3, foto-v1 com paridade do
// vetor gerado em node:crypto (o mesmo testado no agente do Celita), lotes
// nav-v1 e a escolha da foto por consultas por chave.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:controle_de_aula/src/cloud/archive_store.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/ui/archive_page.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String h) => [
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ];

final Map<String, dynamic> _fixture =
    jsonDecode(File('test/fixtures/foto-v1.json').readAsStringSync())
        as Map<String, dynamic>;

class _FakeIndex implements PhotoIndex {
  final Map<String, SplayTreeMap<int, PhotoRef>> byDay = {};
  final List<String> calls = [];

  void add(String day, int ts, String uid) {
    (byDay[day] ??= SplayTreeMap())[ts] = PhotoRef(
      day: day,
      ts: ts,
      uid: uid,
      random: 'A' * 22,
    );
  }

  @override
  Future<PhotoRef?> exact(String day, int ts) async {
    calls.add('exact $day ${ts13(ts)}');
    return byDay[day]?[ts];
  }

  @override
  Future<PhotoRef?> lastBetween(String day, int from, int to) async {
    calls.add('antes $day ${ts13(from)}..${ts13(to)}');
    final m = byDay[day];
    if (m == null) return null;
    final k = m.lastKeyBefore(to + 1);
    return k != null && k >= from ? m[k] : null;
  }

  @override
  Future<PhotoRef?> firstFrom(String day, int from) async {
    calls.add('depois $day ${ts13(from)}');
    final m = byDay[day];
    if (m == null) return null;
    final k = m.firstKeyAfter(from - 1);
    return k != null ? m[k] : null;
  }
}

void main() {
  group('dia em UTC−3 (3.0)', () {
    test('vetores do fixture (perto da meia-noite)', () {
      final dias = _fixture['dias'] as List;
      expect(dias, isNotEmpty);
      for (final v in dias) {
        final m = v as Map;
        expect(dayOf((m['ts'] as num).toInt()), m['dia'], reason: '${m['ts']}');
      }
    });

    test('dayStartMs é 03:00 UTC do dia e volta pelo dayOf', () {
      final inicio = dayStartMs('2026-09-28');
      expect(inicio, DateTime.utc(2026, 9, 28, 3).millisecondsSinceEpoch);
      expect(dayOf(inicio), '2026-09-28');
      expect(dayOf(inicio - 1), '2026-09-27');
    });

    test('recentDays: hoje e os 14 anteriores, sem repetir', () {
      final dias = recentDays(DateTime.utc(2026, 3, 1, 2, 59).millisecondsSinceEpoch);
      expect(dias.length, 15);
      expect(dias.first, '2026-02-28');
      expect(dias[1], '2026-02-27');
      expect(dias.last, '2026-02-14');
      expect(dias.toSet().length, 15);
    });

    test('ts13 completa com zeros à esquerda', () {
      expect(ts13(1790000000123), '1790000000123');
      expect(ts13(123), '0000000000123');
    });
  });

  group('foto-v1 (3.1)', () {
    final key = _hex(_fixture['keyHex'] as String);
    final nonce = _hex(_fixture['nonceHex'] as String);
    final header = Map<String, dynamic>.from(_fixture['header'] as Map);
    final jpeg = _hex(_fixture['jpegHex'] as String);
    final objeto = base64.decode(_fixture['objetoB64'] as String);
    final ts = (header['ts'] as num).toInt();

    test('cabeçalho compacto do Dart casa com o do vetor', () {
      expect(jsonEncode(header), _fixture['headerJson']);
    });

    test('sealPhoto gera o objeto do vetor byte a byte', () async {
      final sealed = await SessionCrypto(key).sealPhoto(header, jpeg, nonce: nonce);
      expect(sealed, objeto);
    });

    test('openPhoto abre o objeto do vetor', () async {
      final foto = await SessionCrypto(key).openPhoto(objeto, ts: ts);
      expect(foto.header, header);
      expect(foto.jpeg, jpeg);
      expect(foto.motivo, 'bloqueado');
      expect(foto.user, 'joão.aluno');
      expect(foto.login, 1789999000000);
    });

    test('openPhoto recusa ts do nome diferente do cabeçalho', () async {
      expect(
        () => SessionCrypto(key).openPhoto(objeto, ts: ts + 1),
        throwsFormatException,
      );
    });

    test('openPhoto recusa chave errada e objeto adulterado', () async {
      final outra = SessionCrypto(List<int>.generate(32, (i) => 255 - i));
      expect(
        () => outra.openPhoto(objeto, ts: ts),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final adulterado = Uint8List.fromList(objeto)..[20] ^= 1;
      expect(
        () => SessionCrypto(key).openPhoto(adulterado, ts: ts),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('openPhoto recusa v != 1 e type errado', () async {
      final c = SessionCrypto(key);
      final v2 = await c.sealPhoto({...header, 'v': 2}, jpeg);
      expect(() => c.openPhoto(v2, ts: ts), throwsFormatException);
      final outroTipo = await c.sealPhoto({...header, 'type': 'camera_snapshot'}, jpeg);
      expect(() => c.openPhoto(outroTipo, ts: ts), throwsFormatException);
    });
  });

  group('lotes nav-v1 (3.2)', () {
    final crypto = SessionCrypto(List<int>.generate(32, (i) => i));

    Future<Map<String, dynamic>> lote(
      String user,
      int login,
      List<Map<String, dynamic>> events, {
      String type = 'archived_nav',
      SessionCrypto? com,
    }) async =>
        {
          'env': await (com ?? crypto).seal({
            'v': 1,
            'type': type,
            'user': user,
            'login': login,
            'events': events,
          }),
          'ts': 1,
        };

    test('decifra, agrupa por entrada, ordena por ts e pula ilegíveis', () async {
      final raw = {
        '-b': await lote('ana', 2000, [
          {'ts': 2300, 'url': 'https://c.com/', 'title': 'C'},
          {'ts': 2100, 'url': 'https://a.com/', 'title': 'A', 'acao': 'bloqueado', 'foto': 2100},
        ]),
        '-a': await lote('ana', 2000, [
          {'ts': 2200, 'url': 'https://b.com/', 'title': 'B', 'acao': 'alerta'},
          {'ts': 2100, 'url': 'https://a.com/', 'title': 'A', 'acao': 'bloqueado', 'foto': 2100},
        ]),
        '-c': await lote('bia', 1000, [
          {'ts': 1500, 'url': 'https://d.com/', 'acao': 'outra'},
          {'ts': 'x', 'url': 'https://ruim.com/'},
        ]),
        '-d': await lote(
          'ana',
          2000,
          [
            {'ts': 2400, 'url': 'https://x.com/'},
          ],
          type: 'archived_photo',
        ),
        '-e': await lote(
          'ana',
          2000,
          [
            {'ts': 2500, 'url': 'https://y.com/'},
          ],
          com: SessionCrypto(List<int>.generate(32, (i) => 255 - i)),
        ),
        '-f': {'env': 'não é base64', 'ts': 1},
        '-g': {'ts': 1},
      };
      final dia = await parseNavDay(raw, crypto);
      expect(dia.unreadable, 4);
      expect(dia.isEmpty, isFalse);
      expect(dia.sessions.map((s) => '${s.user}@${s.login}'), ['bia@1000', 'ana@2000']);

      final bia = dia.sessions.first.events;
      expect(bia.length, 1);
      expect(bia.single.title, '');
      expect(bia.single.action, isNull);

      final ana = dia.sessions.last.events;
      expect(ana.map((e) => e.ts), [2100, 2200, 2300]);
      expect(ana[0].action, 'bloqueado');
      expect(ana[0].photoTs, 2100);
      expect(ana[1].action, 'alerta');
      expect(ana[1].photoTs, isNull);
    });

    test('dia sem nó = vazio, sem ilegíveis', () async {
      final dia = await parseNavDay(null, crypto);
      expect(dia.isEmpty, isTrue);
      expect(dia.unreadable, 0);
    });
  });

  group('índice de fotos', () {
    test('PhotoRef monta o caminho do Storage e valida a entrada', () {
      final r = PhotoRef.parse('2026-09-28', '1790000000123', {
        'u': 'uidDoAgente123',
        'r': 'abcdefghijklmnopqrstuv',
      });
      expect(r!.path, 'fotos/uidDoAgente123/2026-09-28/1790000000123_abcdefghijklmnopqrstuv.bin');
      expect(PhotoRef.parse('2026-09-28', '179', {'u': 'x', 'r': 'a' * 22}), isNull);
      expect(PhotoRef.parse('2026-09-28', '1790000000123', {'u': '../x', 'r': 'a' * 22}), isNull);
      expect(PhotoRef.parse('2026-09-28', '1790000000123', {'u': 'x', 'r': 'curto'}), isNull);
      expect(PhotoRef.parse('2026-09-28', '1790000000123', null), isNull);
    });

    test('poda de reserva: hoje−15 a hoje−45, nav e fotos, por PC', () {
      final agora = DateTime.utc(2026, 9, 28, 12).millisecondsSinceEpoch;
      final p = prunePaths(['pc1', 'pc2'], agora);
      expect(p.length, 2 * 2 * 31);
      expect(p.values.every((v) => v == null), isTrue);
      expect(p.containsKey('archive/pc1/nav/2026-09-13'), isTrue);
      expect(p.containsKey('archive/pc2/fotos/2026-08-14'), isTrue);
      expect(p.containsKey('archive/pc1/nav/2026-09-14'), isFalse);
      expect(p.containsKey('archive/pc1/nav/2026-08-13'), isFalse);
    });
  });

  group('escolha da foto (3.3)', () {
    const dia = '2026-09-28';
    final inicioDia = dayStartMs(dia);
    final login = inicioDia + 3600000; // entrou 1h depois do início do dia
    final sessao = ArchivedSession(user: 'ana', login: login);
    const min = 60000;

    late _FakeIndex index;
    late Map<int, Map<String, dynamic>> headers;
    late List<int> abertas;

    Future<ArchivedPhoto> abrir(PhotoRef ref) async {
      abertas.add(ref.ts);
      final h = headers[ref.ts];
      if (h == null) throw const PhotoException(PhotoFailure.deleted);
      return ArchivedPhoto(header: h, jpeg: Uint8List(0));
    }

    void foto(int ts, {String user = 'ana', int? doLogin}) {
      index.add(dia, ts, 'uid');
      headers[ts] = {
        'v': 1,
        'type': 'archived_photo',
        'ts': ts,
        'motivo': 'periodica',
        'user': user,
        'login': doLogin ?? login,
      };
    }

    Future<ChosenPhoto?> escolher(ArchivedNavEvent e, {ArchivedSession? s}) =>
        pickPhoto(day: dia, session: s ?? sessao, event: e, index: index, open: abrir);

    ArchivedNavEvent ev(int ts, {int? photoTs}) =>
        ArchivedNavEvent(ts: ts, url: 'https://x.com/', title: 'X', photoTs: photoTs);

    setUp(() {
      index = _FakeIndex();
      headers = {};
      abertas = [];
    });

    test('1) foto marcada no evento e presente no índice vence', () async {
      final t = login + 40 * min;
      foto(t - 30 * min);
      foto(t + 1 * min);
      foto(t);
      final r = await escolher(ev(t, photoTs: t));
      expect(r!.ref.ts, t);
      expect(index.calls, ['exact $dia ${ts13(t)}']);
    });

    test('1) foto marcada de outro dia (virada da meia-noite) é achada', () async {
      final antes = inicioDia - 30000; // 23:59:30 do dia anterior
      final ontem = dayOf(antes);
      expect(ontem, isNot(dia));
      index.add(ontem, antes, 'uid');
      headers[antes] = {'ts': antes, 'login': login, 'user': 'ana'};
      final r = await escolher(ev(inicioDia + 10000, photoTs: antes));
      expect(r!.ref.ts, antes);
      expect(r.ref.day, ontem);
      expect(index.calls, ['exact $ontem ${ts13(antes)}']);
    });

    test('1→2) foto marcada ausente do índice cai na mais próxima', () async {
      final t = login + 40 * min;
      foto(t - 10 * min);
      final r = await escolher(ev(t, photoTs: t));
      expect(r!.ref.ts, t - 10 * min);
    });

    test('2) antes mais perto que depois: antes, sem abrir a de depois', () async {
      final t = login + 40 * min;
      foto(t - 2 * min);
      foto(t + 10 * min);
      final r = await escolher(ev(t));
      expect(r!.ref.ts, t - 2 * min);
      expect(abertas, [t - 2 * min]);
      expect(index.calls, [
        'antes $dia ${ts13(login)}..${ts13(t)}',
        'depois $dia ${ts13(t)}',
      ]);
    });

    test('2) depois mais perto e da mesma entrada: depois', () async {
      final t = login + 40 * min;
      foto(t - 10 * min);
      foto(t + 1 * min);
      final r = await escolher(ev(t));
      expect(r!.ref.ts, t + 1 * min);
    });

    test('2) depois de outra entrada (login ou conta): volta para antes', () async {
      final t = login + 40 * min;
      foto(t - 10 * min);
      foto(t + 1 * min, doLogin: login + 39 * min);
      expect((await escolher(ev(t)))!.ref.ts, t - 10 * min);

      index = _FakeIndex();
      headers = {};
      foto(t - 10 * min);
      foto(t + 1 * min, user: 'bia');
      expect((await escolher(ev(t)))!.ref.ts, t - 10 * min);
    });

    test('2) depois de outra entrada e sem antes: nenhuma', () async {
      final t = login + 40 * min;
      foto(t + 1 * min, user: 'bia');
      expect(await escolher(ev(t)), isNull);
    });

    test('2) antes da entrada na conta não conta', () async {
      final t = login + 5 * min;
      foto(login - 1 * min);
      expect(await escolher(ev(t)), isNull);
    });

    test('2) entrada no dia anterior: antes começa no início do dia', () async {
      final ontem = ArchivedSession(user: 'ana', login: inicioDia - 3600000);
      final t = inicioDia + 10 * min;
      index.add(dia, inicioDia + 1 * min, 'uid');
      headers[inicioDia + 1 * min] = {'ts': inicioDia + 1 * min};
      final r = await escolher(ev(t), s: ontem);
      expect(r!.ref.ts, inicioDia + 1 * min);
      expect(index.calls.first, 'antes $dia ${ts13(inicioDia)}..${ts13(t)}');
    });

    test('3) sem nenhuma foto: null', () async {
      expect(await escolher(ev(login + 5 * min)), isNull);
    });

    test('depois que falha ao abrir, sem antes: o erro sobe', () async {
      final t = login + 5 * min;
      index.add(dia, t + 1 * min, 'uid'); // no índice, mas sem objeto
      expect(
        () => escolher(ev(t)),
        throwsA(isA<PhotoException>().having((e) => e.failure, 'failure', PhotoFailure.deleted)),
      );
    });
  });

  group('legenda da foto', () {
    test('distância em min/h, antes e depois', () {
      expect(distanciaDaFoto(60000, 0), '1 min depois deste site');
      expect(distanciaDaFoto(0, 5 * 60000), '5 min antes deste site');
      expect(distanciaDaFoto(10000, 0), 'no mesmo minuto deste site');
      expect(distanciaDaFoto(125 * 60000, 0), '2 h 5 min depois deste site');
      expect(distanciaDaFoto(0, 60 * 60000), '1 h antes deste site');
    });

    test('motivo e conta', () {
      final ts = DateTime(2026, 9, 28, 10, 5).millisecondsSinceEpoch;
      final foto = ArchivedPhoto(
        header: {'ts': ts, 'motivo': 'login', 'user': 'ana'},
        jpeg: Uint8List(0),
      );
      expect(
        legendaDaFoto(foto, ts - 60000),
        'Foto das 10:05 — ao entrar na conta · conta ana\n1 min depois deste site',
      );
    });

    test('rótulo do dia', () {
      expect(rotuloDoDia('2026-09-28', 0), 'Hoje');
      expect(rotuloDoDia('2026-09-27', 1), 'Ontem');
      expect(rotuloDoDia('2026-09-23', 5), 'qua 23/09');
    });
  });
}
