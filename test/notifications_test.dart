// Testes das notificações: throttle do NotificationService (relógio injetado)
// e o hook onNovosEventos do SessionRegistry (1º report nunca notifica).

import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/service/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
