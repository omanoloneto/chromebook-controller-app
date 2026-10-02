// Mensagens novas do protocolo de turma (texto em claro, antes de cifrar):
// builders de chat_message, unblock_result, set_lock, set_exam, set_monitor,
// close_all_tabs{fimDeAula} e os parsers UpMessage, Aplicado, EstadoTrava,
// EstadoProva e Miniatura. Exemplos iguais aos de docs/protocolo.md.

import 'dart:convert';

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/util/ids.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _up(String type, Map<String, dynamic> payload, {String mid = 'pJ3x0Qm2aZr9Lw1K'}) => {
      'sid': 1767369500000,
      'seq': 3,
      'ts': 1767369540123,
      'v': 1,
      'type': type,
      'mid': mid,
      'payload': payload,
    };

void main() {
  group('builders', () {
    test('chat_message: texto e de cortados, mid próprio, id aleatório', () {
      final cmd = buildChatMessage(texto: '  Abram a página 12.  ', de: 'Prof. Manoel', mid: 'Zr9Lw1KpJ3x0Qm2a');
      expect(cmd['type'], 'chat_message');
      expect(formatoDeId.hasMatch(cmd['id'] as String), isTrue);
      expect(cmd['payload'], {'texto': 'Abram a página 12.', 'de': 'Prof. Manoel', 'mid': 'Zr9Lw1KpJ3x0Qm2a'});
      final longo = buildChatMessage(texto: '😀' * 600, de: 'x' * 80, mid: 'm');
      final p = longo['payload'] as Map;
      expect((p['texto'] as String).runes.length, 500, reason: 'caps contam code points');
      expect((p['de'] as String).length, 60);
    });

    test('unblock_result aprovado leva só o rev do caminho usado', () {
      final ok = buildUnblockResult(mid: 'u1', site: 'pt.khanacademy.org', approved: true, rulesRev: 7, motivo: 'x');
      expect(ok['type'], 'unblock_result');
      expect(ok['payload'], {'mid': 'u1', 'site': 'pt.khanacademy.org', 'approved': true, 'rulesRev': 7});
      final prova = buildUnblockResult(mid: 'u1', site: 'a.com', approved: true, examRev: 9);
      expect((prova['payload'] as Map)['examRev'], 9);
      expect((prova['payload'] as Map).containsKey('rulesRev'), isFalse);
    });

    test('unblock_result recusado leva o motivo (≤ 200) só se houver', () {
      final r = buildUnblockResult(mid: 'u1', site: 'youtube.com', approved: false, motivo: 'Depois da prova.', rulesRev: 3);
      expect(r['payload'], {'mid': 'u1', 'site': 'youtube.com', 'approved': false, 'motivo': 'Depois da prova.'});
      final semMotivo = buildUnblockResult(mid: 'u1', site: 'youtube.com', approved: false, motivo: '   ');
      expect((semMotivo['payload'] as Map).containsKey('motivo'), isFalse);
      final longo = buildUnblockResult(mid: 'u', site: 'a.com', approved: false, motivo: 'm' * 300);
      expect(((longo['payload'] as Map)['motivo'] as String).length, 200);
    });

    test('set_lock: texto ≤ 200, vazio vira o padrão', () {
      final l = buildSetLock(rev: 1767369600000, on: true, texto: 'Olhos no professor', mute: true, ate: 1767370800000);
      expect(l['type'], 'set_lock');
      expect(l['payload'], {'rev': 1767369600000, 'on': true, 'texto': 'Olhos no professor', 'mute': true, 'ate': 1767370800000});
      final vazio = buildSetLock(rev: 1, on: false, texto: ' ', mute: false, ate: 2);
      expect((vazio['payload'] as Map)['texto'], kTravaTextoPadrao);
      final longo = buildSetLock(rev: 1, on: true, texto: 'a' * 300, mute: true, ate: 2);
      expect(((longo['payload'] as Map)['texto'] as String).length, 200);
    });

    test('set_exam: allow normalizado sem repetição; inicio só http(s)', () {
      final e = buildSetExam(
        rev: 1767369600000,
        on: true,
        allow: ['khanacademy.org', 'https://KhanAcademy.org/', '', 'wikipedia.org'],
        inicio: 'https://escola.edu.br/portal',
        ate: 1767376800000,
      );
      expect(e['type'], 'set_exam');
      expect(e['payload'], {
        'rev': 1767369600000,
        'on': true,
        'allow': [
          {'pattern': 'khanacademy.org'},
          {'pattern': 'wikipedia.org'},
        ],
        'inicio': 'https://escola.edu.br/portal',
        'ate': 1767376800000,
      });
      for (final ruim in ['javascript:alert(1)', 'file:///etc/passwd', 'https://${'a' * 2050}', '']) {
        final x = buildSetExam(rev: 1, on: true, allow: const [], inicio: ruim, ate: 2);
        expect((x['payload'] as Map).containsKey('inicio'), isFalse, reason: ruim);
      }
      final muitos = buildSetExam(rev: 1, on: true, allow: [for (var i = 0; i < 1200; i++) 's$i.com'], ate: 2);
      expect(((muitos['payload'] as Map)['allow'] as List).length, 1000);
    });

    test('set_monitor e close_all_tabs com fimDeAula', () {
      expect(buildSetMonitor(rev: 1, ate: 2)['payload'], {'rev': 1, 'ate': 2});
      expect(buildCloseAllTabs(closeWindows: true, fimDeAula: true)['payload'], {'closeWindows': true, 'fimDeAula': true});
      expect(buildCloseAllTabs()['payload'], {'closeWindows': false}, reason: 'cliente antigo ignora; o "limpar abas" não leva');
    });

    test('os tipos reservados saíram', () {
      // lock_screen / unlock_screen / focus_mode foram aposentados (§9).
      const tipos = [
        MessageType.chatMessage,
        MessageType.unblockResult,
        MessageType.setLock,
        MessageType.setExam,
        MessageType.setMonitor,
        MessageType.thumbSnapshot,
      ];
      expect(tipos, ['chat_message', 'unblock_result', 'set_lock', 'set_exam', 'set_monitor', 'thumb_snapshot']);
    });
  });

  group('UpMessage.fromMap', () {
    test('chat do exemplo do protocolo', () {
      final m = UpMessage.fromMap(_up('chat', {'texto': 'não consigo abrir o site'}))!;
      expect(m.type, UpType.chat);
      expect(m.mid, 'pJ3x0Qm2aZr9Lw1K');
      expect(m.texto, 'não consigo abrir o site');
      expect(m.sid, 1767369500000);
      expect(m.seq, 3);
    });

    test('chat vazio, sem texto ou longo', () {
      expect(UpMessage.fromMap(_up('chat', {'texto': '   '})), isNull);
      expect(UpMessage.fromMap(_up('chat', {})), isNull);
      expect(UpMessage.fromMap(_up('chat', {'texto': 5})), isNull);
      expect(UpMessage.fromMap(_up('chat', {'texto': 'x' * 900}))!.texto!.length, 500);
    });

    test('unblock_request válido', () {
      final m = UpMessage.fromMap(_up('unblock_request', {
        'site': 'youtube.com',
        'url': 'https://www.youtube.com/watch?v=1',
        'motivo': 'vídeo da aula',
        'bloqueio': 'prova',
      },),)!;
      expect(m.site, 'youtube.com');
      expect(m.url, 'https://www.youtube.com/watch?v=1');
      expect(m.motivo, 'vídeo da aula');
      expect(m.bloqueio, 'prova');
      final semMotivo = UpMessage.fromMap(_up('unblock_request', {'site': 'youtube.com', 'url': ''}))!;
      expect(semMotivo.motivo, '');
      expect(semMotivo.bloqueio, 'regra');
    });

    test('unblock_request inválido é descartado calado', () {
      for (final p in <Map<String, dynamic>>[
        {'site': 'com.br', 'url': ''},
        {'site': 'YouTube.com', 'url': ''},
        {'site': 'youtube.com', 'url': 'https://khanacademy.org/'},
        {'site': 'youtube.com', 'url': 'https://youtube.com/${'a' * 500}'},
        {'url': 'https://youtube.com/'},
      ]) {
        expect(UpMessage.fromMap(_up('unblock_request', p)), isNull, reason: '$p');
      }
    });

    test('raise_hand, tipo desconhecido, mid e cabeçalho', () {
      expect(UpMessage.fromMap(_up('raise_hand', {}))!.type, UpType.raiseHand);
      expect(UpMessage.fromMap(_up('lock_screen', {})), isNull);
      expect(UpMessage.fromMap(_up('chat', {'texto': 'oi'}, mid: '')), isNull);
      expect(UpMessage.fromMap(_up('chat', {'texto': 'oi'}, mid: 'a/b')), isNull);
      final semSeq = _up('chat', {'texto': 'oi'})..remove('seq');
      expect(UpMessage.fromMap(semSeq), isNull);
    });
  });

  group('tab_report.aplicado', () {
    test('parse com caps; ausente = cliente antigo', () {
      final r = TabReport.fromMap({
        'type': 'tab_report',
        'tabs': const [],
        'events': const [],
        'aplicado': {
          'trava': {'rev': 10, 'on': true},
          'prova': {'rev': 11, 'on': false, 'erro': 'navegador_antigo'},
          'acks': [
            for (var i = 0; i < 25; i++) {'id': 'id$i', 'ok': i.isEven, if (i.isOdd) 'error': 'x' * 60},
            {'id': 'y' * 40, 'ok': true},
          ],
        },
      })!;
      final a = r.aplicado!;
      expect(a.trava!.rev, 10);
      expect(a.trava!.on, isTrue);
      expect(a.trava!.erro, isNull);
      expect(a.prova!.erro, 'navegador_antigo');
      expect(a.acks, hasLength(20));
      expect(a.acks[1].error!.length, 40);
      expect(TabReport.fromMap({'type': 'tab_report'})!.aplicado, isNull);
    });
  });

  group('estado lido de state/lock e state/exam', () {
    test('EstadoTrava.fromCommand e vigência', () {
      final cmd = buildSetLock(rev: 5, on: true, texto: 'Atenção', mute: true, ate: 1000);
      final t = EstadoTrava.fromCommand(jsonDecode(jsonEncode(cmd)) as Map<String, dynamic>)!;
      expect(t.on, isTrue);
      expect(t.texto, 'Atenção');
      expect(t.vigente(999), isTrue);
      expect(t.vigente(1000), isFalse, reason: 'prazo vencido: o PC já destravou');
      expect(EstadoTrava.fromCommand(buildSetMonitor(rev: 1, ate: 2)), isNull);
    });

    test('EstadoProva.fromCommand', () {
      final cmd = buildSetExam(rev: 5, on: true, allow: ['a.com'], inicio: 'https://e.br/', ate: 1000);
      final p = EstadoProva.fromCommand(jsonDecode(jsonEncode(cmd)) as Map<String, dynamic>)!;
      expect(p.allow, ['a.com']);
      expect(p.inicio, 'https://e.br/');
      expect(p.vigente(10), isTrue);
    });
  });

  group('Miniatura.fromMap', () {
    test('imagem e marcador', () {
      final img = Miniatura.fromMap({
        'v': 1,
        'type': 'thumb_snapshot',
        'jpegB64': base64Encode([0xff, 0xd8, 0xff]),
        'w': 480,
        'h': 270,
      }, ts: 7,)!;
      expect(img.jpeg, [0xff, 0xd8, 0xff]);
      expect(img.motivo, isNull);
      expect(img.ts, 7);
      final marcador = Miniatura.fromMap({'type': 'thumb_snapshot', 'jpegB64': null, 'motivo': 'sem_permissao'}, ts: 1)!;
      expect(marcador.jpeg, isNull);
      expect(marcador.motivo, 'sem_permissao');
      expect(Miniatura.fromMap({'type': 'screen_snapshot'}, ts: 1), isNull);
      expect(Miniatura.fromMap({'type': 'thumb_snapshot', 'jpegB64': '%%%'}, ts: 1), isNull);
    });
  });
}
