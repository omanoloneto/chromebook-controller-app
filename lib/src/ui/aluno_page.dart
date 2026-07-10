// Ficha do aluno: aulas em que participou (data) e, dentro de cada aula,
// o que acessou. Dados vêm do /history do Firebase, cifrados — só este
// celular decifra (chave derivada da keypair do professor).

import 'package:flutter/material.dart';

import '../cloud/history_store.dart';
import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import 'device_page.dart' show dominioDe;

String _data(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year} $hh:$min';
}

class AlunoPage extends StatefulWidget {
  const AlunoPage({super.key, required this.pairing, required this.aluno});

  final PairingController pairing;
  final String aluno;

  @override
  State<AlunoPage> createState() => _AlunoPageState();
}

class _AlunoPageState extends State<AlunoPage> {
  late Future<List<AulaMeta>> _aulas = widget.pairing.aulasDoAluno(widget.aluno);

  void _recarregar() {
    setState(() {
      _aulas = widget.pairing.aulasDoAluno(widget.aluno);
    });
  }

  Future<void> _apagarAula(AulaMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar esta aula'),
        content: Text(
          'Apagar os registros de ${_data(meta.inicio)} (${meta.turma})? '
          'Remove a aula inteira do histórico, de todos os alunos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.pairing.apagarAulaDoHistorico(meta.sessionId);
      _recarregar();
    }
  }

  Future<void> _apagarTudoDoAluno() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar histórico do aluno'),
        content: Text(
          'Apagar TODOS os registros de ${widget.aluno}, em todas as aulas? '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.pairing.apagarHistoricoDoAluno(widget.aluno);
      _recarregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.aluno),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (v) {
              if (v == 'apagar') _apagarTudoDoAluno();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'apagar',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Apagar todo o histórico deste aluno'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<AulaMeta>>(
        future: _aulas,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Não foi possível carregar: ${snap.error}'),
              ),
            );
          }
          final aulas = snap.data ?? const [];
          if (aulas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma aula registrada para este aluno.\n\n'
                  'Os registros aparecem quando o aluno é vinculado a um PC '
                  'durante uma aula.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _recarregar(),
            child: ListView.separated(
              itemCount: aulas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final meta = aulas[i];
                final emAndamento = meta.fim == null;
                return ListTile(
                  leading: Icon(
                    emAndamento ? Icons.play_circle_outline : Icons.history_edu,
                  ),
                  title: Text(_data(meta.inicio)),
                  subtitle: Text(
                    '${meta.turma}${emAndamento ? ' · em andamento' : ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Opções da aula',
                    onSelected: (v) {
                      if (v == 'apagar') _apagarAula(meta);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'apagar',
                        child: Text('Apagar esta aula'),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AulaHistoricoPage(
                        pairing: widget.pairing,
                        aluno: widget.aluno,
                        meta: meta,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Eventos de UM aluno numa aula.
class AulaHistoricoPage extends StatelessWidget {
  const AulaHistoricoPage({
    super.key,
    required this.pairing,
    required this.aluno,
    required this.meta,
  });

  final PairingController pairing;
  final String aluno;
  final AulaMeta meta;

  String _hora(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(aluno),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${meta.turma} · ${_data(meta.inicio)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<NavEvent>>(
        future: pairing.eventosDoAluno(meta.sessionId, aluno),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final eventos = snap.data ?? const [];
          if (eventos.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum acesso registrado nesta aula.'),
              ),
            );
          }
          return ListView.builder(
            itemCount: eventos.length,
            itemBuilder: (_, i) {
              final e = eventos[i];
              return ListTile(
                dense: true,
                leading: Text(
                  _hora(e.ts),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                title: Text(
                  e.title.isEmpty ? e.url : e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(dominioDe(e.url)),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Opções do link',
                  onSelected: (v) {
                    if (v == 'telao') {
                      pairing.abrirNoPcProfessor(e.url);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Abrindo no PC do professor…'),
                          ),
                        );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'telao',
                      enabled: pairing.pcProfessorOnline,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.co_present),
                        title: const Text('Abrir no PC do professor'),
                        subtitle: pairing.pcProfessorOnline
                            ? null
                            : Text(
                                pairing.pcProfessorId == null
                                    ? 'nenhum PC marcado como do professor'
                                    : 'PC do professor está offline',
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
