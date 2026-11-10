// "Saúde da frota" (Ajustes): os PCs com Celita OS que precisam de atenção
// primeiro, cada um com os motivos, os números que o agente publica e a ação
// que resolve dali mesmo (reiniciar ou atualizar).

import 'package:flutter/material.dart';

import '../cloud/fleet_health.dart';
import '../cloud/pc_health.dart';
import '../commands/command.dart' show AcaoEnergia;
import '../pairing/pairing_controller.dart';
import 'componentes.dart';
import 'energia_controles.dart';

String _gb(double value) =>
    value >= 10 ? '${value.round()} GB' : '${value.toStringAsFixed(1).replaceAll('.', ',')} GB';

String _two(int n) => n.toString().padLeft(2, '0');

String _dayAndTime(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)} às ${_two(d.hour)}:${_two(d.minute)}';

String _disk(DiskVolume v) => '${_gb(v.freeGb)} livres de ${_gb(v.totalGb)}';

/// Motivo de atenção em uma linha, para o professor.
String issueText(FleetHealthEntry entry, HealthIssue issue) {
  final health = entry.health;
  return switch (issue) {
    HealthIssue.updateFailed => 'A atualização do sistema falhou',
    HealthIssue.rebootPending => 'Falta reiniciar para terminar a atualização',
    HealthIssue.osOutdated => entry.session.versaoOs == null
        ? 'Celita OS antigo'
        : 'Celita OS antigo (${entry.session.versaoOs})',
    HealthIssue.wrongWifiKey =>
      'Senha errada do Wi-Fi ${health?.wrongKeyNetworks.join(', ') ?? ''}'.trim(),
    HealthIssue.diskFull => 'Disco quase cheio',
    HealthIssue.storageWear => health?.storageWear == 'urgente'
        ? 'Armazenamento no fim da vida útil'
        : 'Armazenamento desgastado',
    HealthIssue.batteryWorn => 'Bateria gasta (${health?.batteryHealth}% da capacidade)',
    HealthIssue.firmwareBehind =>
      'Firmware antigo (${health?.firmware}; o mais novo é ${entry.newestFirmware})',
    HealthIssue.notSeen => 'Não aparece há ${entry.daysUnseen} dias',
  };
}

class FleetHealthPage extends StatelessWidget {
  const FleetHealthPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saúde da frota')),
      body: ListenableBuilder(
        listenable: pairing,
        builder: (context, _) {
          final entries = pairing.fleetHealth;
          if (entries.isEmpty) {
            return const EstadoVazio(
              icone: Icons.monitor_heart_outlined,
              titulo: 'Nenhum computador com Celita OS',
              texto: 'A saúde aparece aqui quando houver um computador com '
                  'Celita OS conectado.',
            );
          }
          final attention = [
            for (final e in entries)
              if (e.needsAttention) e,
          ];
          final fine = [
            for (final e in entries)
              if (!e.needsAttention) e,
          ];
          return ListView(
            padding: recuoDaLista(context),
            children: [
              if (attention.isNotEmpty)
                GrupoDeOpcoes(
                  titulo: 'Precisa de atenção (${attention.length})',
                  children: [
                    for (final e in attention) _PcTile(pairing: pairing, entry: e),
                  ],
                ),
              if (fine.isNotEmpty)
                GrupoDeOpcoes(
                  titulo: 'Sem problemas (${fine.length})',
                  children: [
                    for (final e in fine) _PcTile(pairing: pairing, entry: e),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PcTile extends StatelessWidget {
  const _PcTile({required this.pairing, required this.entry});

  final PairingController pairing;
  final FleetHealthEntry entry;

  String get _id => entry.session.deviceId;

  Future<void> _update(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await pairing.atualizarPc(_id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? '${entry.name} vai baixar e instalar a atualização sozinho.',
          ),
        ),
      );
  }

  List<String> _details(bool online) {
    final s = entry.session;
    final health = entry.health;
    final days = entry.daysUnseen;
    final seen = online
        ? 'Ligado agora'
        : switch (days) {
            null => 'Ainda não apareceu neste app',
            0 => 'Visto hoje',
            1 => 'Visto ontem',
            _ => 'Visto há $days dias',
          };
    if (health == null) {
      return [
        seen,
        if (s.versaoOs != null) 'Celita OS ${s.versaoOs}',
        'Este Celita OS ainda não informa bateria, disco e firmware.',
      ];
    }
    final battery = [
      if (health.batteryHealth != null) '${health.batteryHealth}% da capacidade',
      if (health.batteryCycles != null) '${health.batteryCycles} ciclos',
    ];
    return [
      seen,
      if (s.versaoOs != null) 'Celita OS ${s.versaoOs}',
      if (health.model != null) 'Modelo ${health.model}',
      if (health.firmware != null) 'Firmware ${health.firmware}',
      if (battery.isNotEmpty) 'Bateria: ${battery.join(', ')}',
      if (health.root case final v?) 'Sistema: ${_disk(v)}',
      if (health.home case final v?) 'Arquivos: ${_disk(v)}',
      if (health.storageWear == 'normal') 'Armazenamento sem desgaste',
      if (health.abruptShutdown ?? false) 'Da última vez desligou sem encerrar o sistema',
      if (s.healthAt case final at?) 'Informado em ${_dayAndTime(at)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final online = pairing.isOnline(entry.session);
    final issues = entry.issues;
    final tone = coresDoTom(context, issues.isEmpty ? Tom.sucesso : Tom.atencao);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final canRestart = online && issues.contains(HealthIssue.rebootPending);
    final canUpdate = online && !canRestart && issues.contains(HealthIssue.osOutdated);
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        issues.isEmpty ? Icons.check_circle_outline : Icons.error_outline,
        color: tone.texto,
      ),
      title: Text(entry.name),
      subtitle: Text(
        issues.isEmpty
            ? (online ? 'Ligado agora' : 'Desligado')
            : issues.map((i) => issueText(entry, i)).join(' · '),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        for (final line in _details(online))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: muted),
          ),
        if (canRestart)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => confirmarEnergiaNoPc(
                context,
                pairing,
                _id,
                entry.name,
                AcaoEnergia.reiniciar,
              ),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reiniciar'),
            ),
          ),
        if (canUpdate)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => _update(context),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Atualizar'),
            ),
          ),
      ],
    );
  }
}
