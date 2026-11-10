// health_report (docs/protocolo.md §3): o app revalida tipos e tetos e ignora
// campo desconhecido.

import 'package:controle_de_aula/src/cloud/pc_health.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _report([Map<String, dynamic> extra = const {}]) => {
      'sid': 1,
      'seq': 1,
      'ts': 1,
      'type': 'health_report',
      'v': 1,
      ...extra,
    };

void main() {
  test('lê todos os campos do protocolo', () {
    final h = PcHealth.fromMap(
      _report({
        'firmware': 'MrChromebox-2609.3',
        'model': 'Bluebird',
        'update': {'state': 'baixado', 'reboot': true},
        'lastShutdown': 'abrupt',
        'battery': {'health': 81, 'cycles': 312},
        'disk': {
          'root': {'freeGb': 12.4, 'totalGb': 28},
          'home': {'freeGb': 1.5, 'totalGb': 20},
        },
        'storageWear': 'aviso',
        'wifi': [
          {'ssid': 'Academico', 'reason': 'wrong_key'},
        ],
      }),
    )!;
    expect(h.firmware, 'MrChromebox-2609.3');
    expect(h.model, 'Bluebird');
    expect(h.updateState, 'baixado');
    expect(h.rebootPending, isTrue);
    expect(h.abruptShutdown, isTrue);
    expect(h.batteryHealth, 81);
    expect(h.batteryCycles, 312);
    expect(h.root!.freeGb, 12.4);
    expect(h.root!.totalGb, 28);
    expect(h.home!.freeGb, 1.5);
    expect(h.storageWear, 'aviso');
    expect(h.wrongKeyNetworks, ['Academico']);
  });

  test('só o cabeçalho: tudo vazio, nada quebra', () {
    final h = PcHealth.fromMap(_report())!;
    expect(h.firmware, isNull);
    expect(h.updateState, isNull);
    expect(h.rebootPending, isFalse);
    expect(h.abruptShutdown, isNull);
    expect(h.batteryHealth, isNull);
    expect(h.root, isNull);
    expect(h.wrongKeyNetworks, isEmpty);
  });

  test('outro tipo de mensagem não é saúde', () {
    expect(PcHealth.fromMap({'type': 'tab_report'}), isNull);
    expect(PcHealth.fromMap({}), isNull);
  });

  test('tipo errado, valor fora da faixa e enum desconhecido viram vazio', () {
    final h = PcHealth.fromMap(
      _report({
        'firmware': 7,
        'model': '   ',
        'update': {'state': 'explodiu', 'reboot': 'sim'},
        'lastShutdown': 'talvez',
        'battery': {'health': 140, 'cycles': -1},
        'disk': {
          'root': {'freeGb': 'muito', 'totalGb': 28},
          'home': 'cheio',
        },
        'storageWear': 'péssimo',
        'wifi': 'Academico',
        'novidade': {'a': 1},
      }),
    )!;
    expect(h.firmware, isNull);
    expect(h.model, isNull);
    expect(h.updateState, isNull);
    expect(h.rebootPending, isFalse);
    expect(h.abruptShutdown, isNull);
    expect(h.batteryHealth, isNull);
    expect(h.batteryCycles, isNull);
    expect(h.root, isNull);
    expect(h.home, isNull);
    expect(h.storageWear, isNull);
    expect(h.wrongKeyNetworks, isEmpty);
  });

  test('tetos: textos cortados e no máximo 5 redes com senha errada', () {
    final h = PcHealth.fromMap(
      _report({
        'firmware': 'f' * 200,
        'model': 'm' * 200,
        'wifi': [
          {'ssid': 's' * 100, 'reason': 'wrong_key'},
          {'ssid': 'Fraca', 'reason': 'weak_signal'},
          {'reason': 'wrong_key'},
          for (var i = 0; i < 10; i++) {'ssid': 'Rede $i', 'reason': 'wrong_key'},
        ],
      }),
    )!;
    expect(h.firmware, hasLength(kMaxHealthFirmware));
    expect(h.model, hasLength(kMaxHealthModel));
    expect(h.wrongKeyNetworks, hasLength(kMaxHealthWifi));
    expect(h.wrongKeyNetworks.first, hasLength(kMaxHealthSsid));
    expect(h.wrongKeyNetworks, isNot(contains('Fraca')));
  });
}
