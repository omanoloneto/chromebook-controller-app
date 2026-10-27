// Testes das notificações: throttle do NotificationService (relógio injetado),
// o card de cada recado (id por PC e tipo; toque no máximo a cada 2 min, numa
// barra do Android de mentira) e o hook onNovosEventos do SessionRegistry
// (1º report nunca notifica).

import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/service/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Barra de notificações do Android, com as regras que contam aqui: o card é
/// a chave (tag, id); notificação nova alerta, a atualização da mesma chave
/// com onlyAlertOnce não; o toque é o PendingIntent do id (requestCode), com o
/// payload do último card mostrado com esse id (FLAG_UPDATE_CURRENT).
class _BarraFalsa {
  final Map<String, Map<String, Object?>> _porChave = {};
  final Map<Object?, Object?> _toquePorId = {};
  final List<String> toques = [];

  List<Map<String, Object?>> get cards => [..._porChave.values];

  /// O professor tira os cards da barra.
  void limpar() => _porChave.clear();

  /// Payload que o app recebe ao tocar no card do PC e tipo [chave].
  String? tocar(String chave) {
    final card = _porChave.values.singleWhere((c) => c['tag'] == chave || '${c['tag']}'.startsWith('$chave|'));
    return _toquePorId[card['id']] as String?;
  }

  Future<Object?> atender(MethodCall call) async {
    final a = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'initialize':
        return true;
      case 'getActiveNotifications':
        return [
          for (final c in _porChave.values) {'id': c['id'], 'tag': c['tag'], 'title': c['title'], 'body': c['body']},
        ];
      case 'cancel':
        _porChave.remove('${a['tag']}#${a['id']}');
        return null;
      case 'show':
        final ps = a['platformSpecifics'] as Map;
        final chave = '${ps['tag']}#${a['id']}';
        if (!_porChave.containsKey(chave) || ps['onlyAlertOnce'] != true) toques.add(chave);
        _porChave[chave] = {'id': a['id'], 'tag': ps['tag'], 'title': a['title'], 'body': a['body']};
        _toquePorId[a['id']] = a['payload'];
        return null;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService.deveDisparar (throttle 2 min)', () {
    test('mesma chave só re-dispara após a janela', () {
      var agora = DateTime(2026, 7, 10, 8, 0, 0);
      final svc = NotificationService(relogio: () => agora);

      expect(svc.deveDisparar('alerta|pc1|youtube.com'), true);
      expect(svc.deveDisparar('alerta|pc1|youtube.com'), false); // imediato
      agora = agora.add(const Duration(minutes: 1, seconds: 59));
      expect(svc.deveDisparar('alerta|pc1|youtube.com'), false); // < 2 min
      agora = agora.add(const Duration(seconds: 2));
      expect(svc.deveDisparar('alerta|pc1|youtube.com'), true); // janela venceu
    });

    test('chaves distintas não se bloqueiam', () {
      final agora = DateTime(2026, 7, 10, 8, 0, 0);
      final svc = NotificationService(relogio: () => agora);
      expect(svc.deveDisparar('alerta|pc1|youtube.com'), true);
      expect(svc.deveDisparar('alerta|pc2|youtube.com'), true); // outro PC
      expect(svc.deveDisparar('bloqueado|pc1|youtube.com'), true); // outro tipo
      expect(svc.deveDisparar('alerta|pc1|tiktok.com'), true); // outro domínio
    });
  });

  group('NotificationService: payload do toque', () {
    test('payload leva deviceId e ts, e volta igual', () {
      final p = NotificationService.montarPayload('pc-9', 1767369600000);
      expect(p, '{"d":"pc-9","ts":1767369600000}');
      final t = NotificationService.lerPayload(p)!;
      expect(t.deviceId, 'pc-9');
      expect(t.ts, 1767369600000);
    });

    test('payload antigo {d, ts} continua valendo (k nulo = alerta de site)', () {
      final t = NotificationService.lerPayload('{"d":"pc-9","ts":1767369600000}')!;
      expect(t.deviceId, 'pc-9');
      expect(t.ts, 1767369600000);
      expect(t.k, isNull);
    });

    test('recado leva k (chat, pedido, mao) e volta igual', () {
      for (final k in ['chat', 'pedido', 'mao']) {
        final p = NotificationService.montarPayload('pc-1', 5, k: k);
        expect(p, '{"d":"pc-1","ts":5,"k":"$k"}');
        expect(NotificationService.lerPayload(p)!.k, k);
      }
      // k estranho não derruba o toque: vira o de alerta (abre o PC).
      final estranho = NotificationService.lerPayload('{"d":"pc","ts":1,"k":"x"}')!;
      expect(estranho.k, isNull);
      expect(estranho.deviceId, 'pc');
    });

    test('notificarRecado aceita só os três tipos', () async {
      final svc = NotificationService();
      expect(
        await svc.notificarRecado(k: 'chat', deviceId: 'pc', ts: 1, titulo: 'Ana', corpo: 'oi'),
        isTrue,
      );
      expect(
        await svc.notificarRecado(k: 'alerta', deviceId: 'pc', ts: 1, titulo: 'x', corpo: 'y'),
        isFalse,
      );
    });

    test('payload ausente ou estranho vira null', () {
      expect(NotificationService.lerPayload(null), isNull);
      expect(NotificationService.lerPayload(''), isNull);
      expect(NotificationService.lerPayload('não é json'), isNull);
      expect(NotificationService.lerPayload('[1,2]'), isNull);
      expect(NotificationService.lerPayload('{"d":"","ts":1}'), isNull);
      expect(NotificationService.lerPayload('{"d":"pc","ts":"1"}'), isNull);
      expect(NotificationService.lerPayload('{"ts":1}'), isNull);
    });

    test('throttle é pelo deviceId, não pelo nome exibido', () async {
      final agora = DateTime(2026, 9, 28, 8);
      final svc = NotificationService(relogio: () => agora);
      expect(
        await svc.notificarAlerta(
          deviceId: 'pc1',
          ts: 1,
          pc: 'Unidade 3',
          dominio: 'youtube.com',
        ),
        true,
      );
      // Mesmo PC com aluno escolhido (nome mudou): continua no throttle.
      expect(
        await svc.notificarAlerta(
          deviceId: 'pc1',
          ts: 2,
          pc: 'Maria',
          dominio: 'youtube.com',
        ),
        false,
      );
      expect(
        await svc.notificarBloqueado(
          deviceId: 'pc2',
          ts: 3,
          pc: 'Maria',
          dominio: 'youtube.com',
        ),
        true,
      );
    });
  });

  group('NotificationService: card do recado (id, tag e toque)', () {
    const t0 = 1767369600000;
    const janela = 120000;

    test('id fixo por PC e tipo, um por card, longe dos alertas e do serviço', () {
      expect(NotificationService.idDoRecado('chat', 'pc-1'), NotificationService.idDoRecado('chat', 'pc-1'));
      final ids = {
        for (var pc = 1; pc <= 60; pc++)
          for (final k in kTiposDeRecado) NotificationService.idDoRecado(k, 'pc-$pc'),
      };
      expect(ids.length, 180, reason: 'cada PC e tipo tem o seu toque');
      for (final id in ids) {
        expect(id, inInclusiveRange(0x40000000, 0x7fffffff));
      }
    });

    test('sem card na barra: toca', () {
      final c = NotificationService.cardDoRecado(k: 'chat', deviceId: 'pc-1', ts: t0, agoraMs: 5, tagsAtivos: const []);
      expect(c.toca, isTrue);
      expect(c.tag, NotificationService.tagDoRecado('chat', 'pc-1', ts: t0, tocouEm: 5));
      expect(c.tag, 'recado|chat|pc-1|$t0|5');
      expect(c.saem, isEmpty);
    });

    test('dentro de 2 min do toque: atualiza o mesmo card, sem tocar', () {
      final na = NotificationService.tagDoRecado('chat', 'pc-1', ts: t0, tocouEm: 1000);
      final c = NotificationService.cardDoRecado(
        k: 'chat',
        deviceId: 'pc-1',
        ts: t0 + 90000,
        agoraMs: 1000 + janela - 1,
        tagsAtivos: [na],
      );
      expect(c.toca, isFalse);
      expect(c.tag, na);
      expect(c.saem, isEmpty);
    });

    test('2 min depois do toque: card novo, que toca e tira o anterior', () {
      final na = NotificationService.tagDoRecado('chat', 'pc-1', ts: t0, tocouEm: 1000);
      final c = NotificationService.cardDoRecado(
        k: 'chat',
        deviceId: 'pc-1',
        ts: t0 + 1,
        agoraMs: 1000 + janela,
        tagsAtivos: [na],
      );
      expect(c.toca, isTrue);
      expect(c.tag, NotificationService.tagDoRecado('chat', 'pc-1', ts: t0 + 1, tocouEm: 1000 + janela));
      expect(c.saem, [na]);
    });

    test('o mesmo recado que tocou não toca de novo, nem bem depois', () {
      final na = NotificationService.tagDoRecado('mao', 'pc-1', ts: t0, tocouEm: 1000);
      final c = NotificationService.cardDoRecado(
        k: 'mao',
        deviceId: 'pc-1',
        ts: t0,
        agoraMs: 1000 + 10 * janela,
        tagsAtivos: [na],
      );
      expect(c.toca, isFalse);
      expect(c.tag, na);
    });

    test('recado mais velho que o que tocou fica de fora', () {
      final na = NotificationService.tagDoRecado('chat', 'pc-1', ts: t0, tocouEm: 1000);
      final c = NotificationService.cardDoRecado(
        k: 'chat',
        deviceId: 'pc-1',
        ts: t0 - 1,
        agoraMs: 1000 + 10 * janela,
        tagsAtivos: [na],
      );
      expect(c.tag, isNull);
      expect(c.toca, isFalse);
    });

    test('só conta o card do mesmo PC e tipo; dois do mesmo, fica o mais novo', () {
      final outros = [
        null,
        'recado|chat|pc-10|$t0|1000',
        NotificationService.tagDoRecado('mao', 'pc-1', ts: t0, tocouEm: 1000),
        'recado|chat|pc-1|lixo',
        'outra coisa',
      ];
      final c = NotificationService.cardDoRecado(k: 'chat', deviceId: 'pc-1', ts: t0, agoraMs: 2000, tagsAtivos: outros);
      expect(c.toca, isTrue, reason: 'nenhum card de chat do pc-1 na barra');
      expect(c.saem, isEmpty);

      final velho = NotificationService.tagDoRecado('chat', 'pc-1', ts: t0, tocouEm: 1000);
      final novo = NotificationService.tagDoRecado('chat', 'pc-1', ts: t0 + 5000, tocouEm: 1001);
      final d = NotificationService.cardDoRecado(
        k: 'chat',
        deviceId: 'pc-1',
        ts: t0 + 6000,
        agoraMs: 2000,
        tagsAtivos: [velho, novo],
      );
      expect(d.toca, isFalse);
      expect(d.tag, novo);
      expect(d.saem, [velho]);
    });
  });

  group('NotificationService.notificarRecado na barra do Android', () {
    const canal = MethodChannel('dexterous.com/flutter/local_notifications');
    const minuto = 60000;
    // Uma virada da janela fixa antiga (múltiplo de 2 min).
    final virada = (DateTime.utc(2026, 10, 27, 16, 4).millisecondsSinceEpoch ~/ 120000) * 120000;
    late _BarraFalsa barra;
    late int agoraLocal;

    Future<NotificationService> servico() async {
      final s = NotificationService(relogio: () => DateTime.fromMillisecondsSinceEpoch(agoraLocal));
      await s.init(pedirPermissao: false);
      return s;
    }

    Future<void> recado(NotificationService s, String k, String pc, int ts, String corpo) =>
        s.notificarRecado(k: k, deviceId: pc, ts: ts, titulo: pc, corpo: corpo);

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      barra = _BarraFalsa();
      agoraLocal = virada;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, barra.atender);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null);
    });

    test('cada card abre o seu PC, também na mesma janela de 2 min', () async {
      final s = await servico();
      await recado(s, 'chat', 'pc-1', virada + 1000, 'oi');
      await recado(s, 'mao', 'pc-2', virada + 2000, 'pc-2');
      await recado(s, 'pedido', 'pc-5', virada + 3000, 'pc-5: site.com');
      expect(barra.cards, hasLength(3));
      expect(barra.toques, hasLength(3));
      final toque = NotificationService.lerPayload(barra.tocar('recado|chat|pc-1'))!;
      expect((toque.deviceId, toque.k), ('pc-1', 'chat'));
      final outro = NotificationService.lerPayload(barra.tocar('recado|pedido|pc-5'))!;
      expect((outro.deviceId, outro.k), ('pc-5', 'pedido'));
    });

    test('chamadas seguidas sem await: um card e um toque', () async {
      final s = await servico();
      await Future.wait([
        recado(s, 'chat', 'pc-3', virada - minuto, 'mensagem 1'),
        recado(s, 'chat', 'pc-3', virada + minuto, 'mensagem 2'),
        recado(s, 'chat', 'pc-3', virada + 3 * minuto, 'mensagem 3'),
      ]);
      expect(barra.cards, hasLength(1));
      expect(barra.toques, hasLength(1));
      expect(barra.cards.single['body'], 'mensagem 3');
    });

    test('dois pedidos a 2 s, um de cada lado da virada da janela: um toque', () async {
      final s = await servico();
      await recado(s, 'pedido', 'pc-6', virada - 1000, 'pc-6: a.com');
      agoraLocal += 2000;
      await recado(s, 'pedido', 'pc-6', virada + 1000, 'pc-6: b.com');
      expect(barra.toques, hasLength(1));
      expect(barra.cards.single['body'], 'pc-6: b.com');
    });

    test('rajada atrasada (reconexão, fila do push) toca uma vez e mostra o mais novo', () async {
      final s = await servico();
      for (var i = 0; i <= 20; i++) {
        await recado(s, 'chat', 'pc-4', virada - 10 * minuto + i * 30000, 'mensagem $i');
        agoraLocal += 50;
      }
      expect(barra.toques, hasLength(1));
      expect(barra.cards.single['body'], 'mensagem 20');
    });

    test('pedido novo com o card na barra: toca de novo só 2 min depois do toque', () async {
      final s = await servico();
      await recado(s, 'mao', 'pc-7', virada, 'pc-7');
      agoraLocal += minuto;
      await recado(s, 'mao', 'pc-7', virada + minuto, 'pc-7');
      expect(barra.toques, hasLength(1), reason: '1 min depois do toque');
      agoraLocal += minuto + 5000;
      await recado(s, 'mao', 'pc-7', virada + 2 * minuto + 5000, 'pc-7');
      expect(barra.toques, hasLength(2));
      expect(barra.cards, hasLength(1), reason: 'o card novo tira o anterior');
    });

    test('o mesmo recado pelo push e pelo app aberto toca uma vez, mesmo atrasado', () async {
      final aberto = await servico(), push = await servico();
      await recado(aberto, 'chat', 'pc-8', virada + 5000, 'oi');
      agoraLocal += 3 * minuto;
      await recado(push, 'chat', 'pc-8', virada + 5000, 'oi');
      expect(barra.toques, hasLength(1));
      expect(barra.cards, hasLength(1));
    });

    test('push atrasado de um recado mais velho não troca o card', () async {
      final s = await servico();
      await recado(s, 'chat', 'pc-9', virada + minuto, 'segunda');
      agoraLocal += 3 * minuto;
      await recado(s, 'chat', 'pc-9', virada, 'primeira');
      expect(barra.toques, hasLength(1));
      expect(barra.cards.single['body'], 'segunda');
    });

    test('card tirado da barra: o próximo toca, também dentro de 2 min', () async {
      final s = await servico();
      await recado(s, 'chat', 'pc-2', virada, 'primeira');
      barra.limpar();
      agoraLocal += 10000;
      await recado(s, 'chat', 'pc-2', virada + 10000, 'segunda');
      expect(barra.toques, hasLength(2));
    });

    test('tipos diferentes do mesmo PC: um card e um toque para cada', () async {
      final s = await servico();
      await recado(s, 'chat', 'pc-1', virada, 'preciso de ajuda');
      await recado(s, 'mao', 'pc-1', virada + 2000, 'pc-1');
      expect(barra.cards, hasLength(2));
      expect(barra.toques, hasLength(2));
    });
  });

  group('SessionRegistry.onNovosEventos', () {
    final chave = List<int>.generate(32, (i) => i);
    NavEvent ev(int ts, String url) => NavEvent(url: url, title: 't', ts: ts);
    TabReport rep(List<NavEvent> events) =>
        TabReport(tabs: const [], events: events);

    test('1º report nunca notifica; seguintes só com eventos inéditos', () {
      final reg = SessionRegistry();
      final recebidos = <NavEvent>[];
      reg.onNovosEventos = (_, novos) => recebidos.addAll(novos);
      reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave);

      // 1º report: histórico antigo da abertura do app — silêncio.
      reg.applyReport('pc1', rep([ev(1, 'https://a.com/'), ev(2, 'https://b.com/')]));
      expect(recebidos, isEmpty);

      // 2º report: 1 evento repetido + 1 inédito — só o inédito chega.
      reg.applyReport('pc1', rep([ev(2, 'https://b.com/'), ev(3, 'https://c.com/')]));
      expect(recebidos.map((e) => e.url), ['https://c.com/']);

      // 3º report: nada novo — callback não dispara.
      recebidos.clear();
      reg.applyReport('pc1', rep([ev(3, 'https://c.com/')]));
      expect(recebidos, isEmpty);
    });

    test('PC do professor: sem histórico, sem alerta, sem eventos', () {
      final reg = SessionRegistry();
      final recebidos = <NavEvent>[];
      var alertaChamado = false;
      reg.onNovosEventos = (_, novos) => recebidos.addAll(novos);
      reg.avaliarAlerta = (_, __) {
        alertaChamado = true;
        return 'dominio.com';
      };
      reg.pcProfessorId = 'prof';
      reg.bind(deviceId: 'prof', label: 'Telão', sessionKey: chave);

      reg.applyReport('prof', rep([ev(1, 'https://a.com/')]));
      reg.applyReport('prof', rep([ev(2, 'https://b.com/')])); // 2º report
      final s = reg.byId('prof')!;
      expect(s.history, isEmpty); // histórico nunca acumula
      expect(s.alerta, isNull);
      expect(alertaChamado, false); // avaliador nem é consultado
      expect(recebidos, isEmpty); // sem notificações
    });

    test('re-bind preserva histórico e volta a silenciar o 1º report', () {
      final reg = SessionRegistry();
      final recebidos = <NavEvent>[];
      reg.onNovosEventos = (_, novos) => recebidos.addAll(novos);
      reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave);
      reg.applyReport('pc1', rep([ev(1, 'https://a.com/')]));

      // Re-pareamento: sessão nova, histórico preservado.
      reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave);
      // 1º report pós re-bind, mesmo com evento inédito: silêncio.
      reg.applyReport('pc1', rep([ev(9, 'https://novo.com/')]));
      expect(recebidos, isEmpty);
      // Depois volta ao normal.
      reg.applyReport('pc1', rep([ev(10, 'https://outro.com/')]));
      expect(recebidos.map((e) => e.url), ['https://outro.com/']);
    });
  });
}
