// Saúde da frota: o que faz um PC com Celita OS precisar de atenção. Puro
// (sem Firebase nem relógio próprio), testado em test/fleet_health_test.dart.

import '../util/natural_sort.dart';
import '../util/versao.dart';
import 'pc_health.dart';
import 'session_registry.dart';

const int kBatteryWornBelow = 60;
const double kDiskMinFreeGb = 2;
const double kDiskMinFreeShare = 0.1;
const int kNotSeenDays = 7;

enum HealthIssue {
  updateFailed,
  rebootPending,
  osOutdated,
  wrongWifiKey,
  diskFull,
  storageWear,
  batteryWorn,
  firmwareBehind,
  notSeen,
}

class FleetHealthEntry {
  const FleetHealthEntry({
    required this.session,
    required this.name,
    required this.issues,
    this.daysUnseen,
    this.newestFirmware,
  });

  final PcSession session;
  final String name;
  final List<HealthIssue> issues;

  /// Dias inteiros sem presença; null = o PC nunca apareceu para este app.
  final int? daysUnseen;

  /// Firmware mais novo entre os PCs do mesmo modelo, quando este está atrás.
  final String? newestFirmware;

  PcHealth? get health => session.health;
  bool get needsAttention => issues.isNotEmpty;
}

bool diskIsFull(DiskVolume? volume) {
  if (volume == null) return false;
  if (volume.freeGb < kDiskMinFreeGb) return true;
  return volume.totalGb > 0 && volume.freeGb / volume.totalGb < kDiskMinFreeShare;
}

/// Uma entrada por PC, por nome ("Unidade 3" antes de "Unidade 12").
List<FleetHealthEntry> buildFleetHealth(
  Iterable<PcSession> sessions, {
  required bool Function(PcSession) osOutdated,
  required String Function(PcSession) nameOf,
  required int nowMs,
}) {
  final all = sessions.toList();
  final newest = _newestFirmwareByFamily(all);
  final entries = <FleetHealthEntry>[];
  for (final s in all) {
    final health = s.health;
    final seenMs = s.lastSeen.millisecondsSinceEpoch;
    final days = seenMs > 0 ? (nowMs - seenMs) ~/ Duration.millisecondsPerDay : null;
    final family = _firmwareFamily(health);
    final best = family == null ? null : newest[family];
    final behind =
        best != null && compararVersoes(health!.firmware!, best) < 0 ? best : null;
    entries.add(
      FleetHealthEntry(
        session: s,
        name: nameOf(s),
        daysUnseen: days,
        newestFirmware: behind,
        issues: [
          if (health?.updateState == 'erro') HealthIssue.updateFailed,
          if (health?.rebootPending ?? false) HealthIssue.rebootPending,
          if (osOutdated(s)) HealthIssue.osOutdated,
          if (health?.wrongKeyNetworks.isNotEmpty ?? false) HealthIssue.wrongWifiKey,
          if (diskIsFull(health?.root) || diskIsFull(health?.home)) HealthIssue.diskFull,
          if (health?.storageWear case 'aviso' || 'urgente') HealthIssue.storageWear,
          if ((health?.batteryHealth ?? 100) < kBatteryWornBelow) HealthIssue.batteryWorn,
          if (behind != null) HealthIssue.firmwareBehind,
          if (days != null && days > kNotSeenDays) HealthIssue.notSeen,
        ],
      ),
    );
  }
  return entries..sort((a, b) => compararNatural(a.name, b.name));
}

// Firmware só se compara entre PCs do mesmo modelo e do mesmo fornecedor: o
// texto antes do primeiro dígito ("MrChromebox-", "Google_Voema.") diz quem é.
String? _firmwareFamily(PcHealth? health) {
  final firmware = health?.firmware;
  final model = health?.model;
  if (firmware == null || model == null) return null;
  final digit = firmware.indexOf(RegExp('[0-9]'));
  if (digit < 0) return null;
  return '$model\n${firmware.substring(0, digit)}';
}

Map<String, String> _newestFirmwareByFamily(List<PcSession> sessions) {
  final newest = <String, String>{};
  for (final s in sessions) {
    final family = _firmwareFamily(s.health);
    if (family == null) continue;
    final firmware = s.health!.firmware!;
    final current = newest[family];
    if (current == null || compararVersoes(firmware, current) > 0) {
      newest[family] = firmware;
    }
  }
  return newest;
}
