// Saúde da frota: quais motivos põem um PC em "Precisa de atenção".

import 'package:controle_de_aula/src/cloud/fleet_health.dart';
import 'package:controle_de_aula/src/cloud/pc_health.dart';
import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

final int _now = DateTime(2026, 11, 10, 9).millisecondsSinceEpoch;
const int _day = Duration.millisecondsPerDay;

PcSession _pc(String id, {PcHealth? health, int? seenDaysAgo = 0}) {
  final s = PcSession(deviceId: id, label: id, crypto: SessionCrypto(List.filled(32, 0)))
    ..health = health;
  if (seenDaysAgo != null) {
    s.lastSeen = DateTime.fromMillisecondsSinceEpoch(_now - seenDaysAgo * _day - 1000);
  }
  return s;
}

List<FleetHealthEntry> _build(List<PcSession> pcs, {Set<String> outdated = const {}}) =>
    buildFleetHealth(
      pcs,
      osOutdated: (s) => outdated.contains(s.deviceId),
      nameOf: (s) => s.label,
      nowMs: _now,
    );

List<HealthIssue> _issues(PcHealth health) => _build([_pc('a', health: health)]).single.issues;

void main() {
  test('PC saudável não tem motivo nenhum', () {
    final issues = _issues(
      const PcHealth(
        firmware: 'MrChromebox-2609.3',
        model: 'Bluebird',
        updateState: 'atualizado',
        abruptShutdown: true,
        batteryHealth: 60,
        batteryCycles: 900,
        root: DiskVolume(freeGb: 3, totalGb: 28),
        home: DiskVolume(freeGb: 2, totalGb: 20),
        storageWear: 'normal',
      ),
    );
    expect(issues, isEmpty);
  });

  test('cada sinal vira o seu motivo', () {
    expect(_issues(const PcHealth(updateState: 'erro')), [HealthIssue.updateFailed]);
    expect(_issues(const PcHealth(rebootPending: true)), [HealthIssue.rebootPending]);
    expect(_issues(const PcHealth(wrongKeyNetworks: ['Academico'])), [HealthIssue.wrongWifiKey]);
    expect(_issues(const PcHealth(storageWear: 'aviso')), [HealthIssue.storageWear]);
    expect(_issues(const PcHealth(storageWear: 'urgente')), [HealthIssue.storageWear]);
    expect(_issues(const PcHealth(batteryHealth: 59)), [HealthIssue.batteryWorn]);
  });

  test('disco: menos de 2 GB ou menos de 10% livre, no sistema ou nos arquivos', () {
    expect(diskIsFull(const DiskVolume(freeGb: 1.9, totalGb: 10)), isTrue);
    expect(diskIsFull(const DiskVolume(freeGb: 9, totalGb: 100)), isTrue);
    expect(diskIsFull(const DiskVolume(freeGb: 10, totalGb: 100)), isFalse);
    expect(diskIsFull(null), isFalse);
    expect(
      _issues(const PcHealth(home: DiskVolume(freeGb: 0.4, totalGb: 20))),
      [HealthIssue.diskFull],
    );
  });

  test('firmware atrás só entre PCs do mesmo modelo e do mesmo fornecedor', () {
    PcHealth h(String firmware, [String model = 'Bluebird']) =>
        PcHealth(firmware: firmware, model: model);
    final entries = _build([
      _pc('velho', health: h('MrChromebox-2509.1')),
      _pc('novo', health: h('MrChromebox-2609.3')),
      _pc('fabrica', health: h('Google_Bluebird.9999.0.0')),
      _pc('outro modelo', health: h('MrChromebox-2409.0', 'Voema')),
      _pc('sem modelo', health: const PcHealth(firmware: 'MrChromebox-2109.0')),
    ]);
    final byName = {for (final e in entries) e.name: e};
    expect(byName['velho']!.issues, [HealthIssue.firmwareBehind]);
    expect(byName['velho']!.newestFirmware, 'MrChromebox-2609.3');
    for (final name in ['novo', 'fabrica', 'outro modelo', 'sem modelo']) {
      expect(byName[name]!.issues, isEmpty, reason: name);
      expect(byName[name]!.newestFirmware, isNull, reason: name);
    }
  });

  test('sumido: mais de 7 dias sem aparecer; quem nunca apareceu não conta', () {
    final entries = _build([
      _pc('a', seenDaysAgo: 7),
      _pc('b', seenDaysAgo: 8),
      _pc('c', seenDaysAgo: null),
    ]);
    expect(entries[0].issues, isEmpty);
    expect(entries[0].daysUnseen, 7);
    expect(entries[1].issues, [HealthIssue.notSeen]);
    expect(entries[1].daysUnseen, 8);
    expect(entries[2].issues, isEmpty);
    expect(entries[2].daysUnseen, isNull);
  });

  test('agente antigo: só a versão do sistema e os dias sem aparecer', () {
    final entries = _build([_pc('a', seenDaysAgo: 30)], outdated: {'a'});
    expect(entries.single.issues, [HealthIssue.osOutdated, HealthIssue.notSeen]);
    expect(entries.single.health, isNull);
  });

  test('ordem natural pelo nome', () {
    final entries = _build([_pc('Unidade 12'), _pc('Unidade 3'), _pc('Unidade 1')]);
    expect(entries.map((e) => e.name), ['Unidade 1', 'Unidade 3', 'Unidade 12']);
  });
}
