// Saúde de um PC: o health_report que o agente do Celita OS deixa em
// /devices/{id}/health (docs/protocolo.md §3). Puro: revalida tipos e tetos e
// ignora campo desconhecido (test/pc_health_test.dart).

import '../commands/command.dart' show MessageType;

const int kMaxHealthFirmware = 60;
const int kMaxHealthModel = 40;
const int kMaxHealthSsid = 32;
const int kMaxHealthWifi = 5;

const Set<String> _updateStates = {
  'erro',
  'verificando',
  'baixando',
  'baixado',
  'atualizado',
  'instalando',
};
const Set<String> _storageWear = {'normal', 'aviso', 'urgente'};

class DiskVolume {
  const DiskVolume({required this.freeGb, required this.totalGb});

  final double freeGb;
  final double totalGb;

  static DiskVolume? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final free = _number(raw['freeGb'], 0, 1e6);
    final total = _number(raw['totalGb'], 0, 1e6);
    if (free == null || total == null) return null;
    return DiskVolume(freeGb: free.toDouble(), totalGb: total.toDouble());
  }
}

class PcHealth {
  const PcHealth({
    this.firmware,
    this.model,
    this.updateState,
    this.rebootPending = false,
    this.abruptShutdown,
    this.batteryHealth,
    this.batteryCycles,
    this.root,
    this.home,
    this.storageWear,
    this.wrongKeyNetworks = const [],
  });

  final String? firmware;
  final String? model;

  /// ESTADO do atualizador do Celita; `erro` também cobre a rede que bloqueia
  /// o servidor de atualização.
  final String? updateState;
  final bool rebootPending;

  /// Como o boot anterior acabou; null = o PC não soube dizer.
  final bool? abruptShutdown;

  /// Capacidade cheia sobre a de fábrica, 0–100.
  final int? batteryHealth;
  final int? batteryCycles;
  final DiskVolume? root;
  final DiskVolume? home;
  final String? storageWear;

  /// Redes salvas que o PC não conseguiu autenticar nas últimas 24 h.
  final List<String> wrongKeyNetworks;

  static PcHealth? fromMap(Map<String, dynamic> m) {
    if (m['type'] != MessageType.healthReport) return null;
    final update = m['update'];
    final battery = m['battery'];
    final disk = m['disk'];
    final state = update is Map ? update['state'] : null;
    final wear = m['storageWear'];
    final shutdown = m['lastShutdown'];
    final networks = <String>[];
    final wifi = m['wifi'];
    if (wifi is List) {
      for (final entry in wifi) {
        if (networks.length >= kMaxHealthWifi) break;
        if (entry is! Map || entry['reason'] != 'wrong_key') continue;
        final ssid = _text(entry['ssid'], kMaxHealthSsid);
        if (ssid != null) networks.add(ssid);
      }
    }
    return PcHealth(
      firmware: _text(m['firmware'], kMaxHealthFirmware),
      model: _text(m['model'], kMaxHealthModel),
      updateState: _updateStates.contains(state) ? state as String : null,
      rebootPending: update is Map && update['reboot'] == true,
      abruptShutdown: switch (shutdown) { 'abrupt' => true, 'clean' => false, _ => null },
      batteryHealth: battery is Map ? _number(battery['health'], 0, 100)?.round() : null,
      batteryCycles: battery is Map ? _number(battery['cycles'], 0, 100000)?.round() : null,
      root: disk is Map ? DiskVolume.fromMap(disk['root']) : null,
      home: disk is Map ? DiskVolume.fromMap(disk['home']) : null,
      storageWear: _storageWear.contains(wear) ? wear as String : null,
      wrongKeyNetworks: List.unmodifiable(networks),
    );
  }
}

num? _number(Object? value, num low, num high) =>
    value is num && value.isFinite && value >= low && value <= high ? value : null;

String? _text(Object? value, int limit) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  return text.length <= limit ? text : text.substring(0, limit);
}
