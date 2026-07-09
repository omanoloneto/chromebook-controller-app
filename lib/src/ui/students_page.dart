// Tela de turmas e alunos: cadastro local (nada vai ao Firebase).
// Nível 1 = turmas; toque abre o nível 2 = alunos da turma.

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _dialogoTurma({int? indice}) async {
    final turmas = widget.pairing.turmas;
    final existente = indice != null ? turmas[indice] : null;
    final ctrl = TextEditingController(text: existente?.nome ?? '');
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Nova turma' : 'Renomear turma'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nome da turma',
            hintText: 'ex.: 2º ano A',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salvo != true || ctrl.text.trim().isEmpty) return;
    if (indice == null) {
      await widget.pairing.adicionarTurma(ctrl.text);
    } else {
      await widget.pairing.renomearTurma(indice, ctrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final turmas = widget.pairing.turmas;
    return Scaffold(
      appBar: AppBar(title: const Text('Turmas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _dialogoTurma(),
        icon: const Icon(Icons.add),
        label: const Text('Nova turma'),
      ),
      body: turmas.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma turma ainda.\n\n'
                  'Cadastre suas turmas e alunos para vincular quem está em '
                  'cada Chromebook durante a aula.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: turmas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = turmas[i];
                return Dismissible(
                  key: ValueKey('turma|${t.nome}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  confirmDismiss: (_) => showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remover turma'),
                      content: Text(
                        'Remover "${t.nome}" e seus ${t.alunos.length} aluno(s)?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remover'),
                        ),
                      ],
                    ),
                  ),
                  onDismissed: (_) => widget.pairing.removerTurma(i),
                  child: ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(t.nome),
                    subtitle: Text('${t.alunos.length} aluno(s)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Renomear turma',
                      onPressed: () => _dialogoTurma(indice: i),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _AlunosPage(
                          pairing: widget.pairing,
                          turmaIndice: i,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Nível 2: alunos de uma turma.
class _AlunosPage extends StatefulWidget {
  const _AlunosPage({required this.pairing, required this.turmaIndice});

  final PairingController pairing;
  final int turmaIndice;

  @override
  State<_AlunosPage> createState() => _AlunosPageState();
}

class _AlunosPageState extends State<_AlunosPage> {
  @override
  void initState() {
    super.initState();
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _dialogoAluno({int? indice}) async {
    final turma = widget.pairing.turmas[widget.turmaIndice];
    final existente = indice != null ? turma.alunos[indice] : null;
    final ctrl = TextEditingController(text: existente ?? '');
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Novo aluno' : 'Renomear aluno'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome do aluno',
            hintText: 'ex.: William',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salvo != true || ctrl.text.trim().isEmpty) return;
    if (indice == null) {
      await widget.pairing.adicionarAluno(widget.turmaIndice, ctrl.text);
    } else {
      await widget.pairing.renomearAluno(widget.turmaIndice, indice, ctrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Turma pode ter sido removida em outra tela.
    if (widget.turmaIndice >= widget.pairing.turmas.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Turma removida')),
        body: const Center(child: Text('Esta turma não existe mais.')),
      );
    }
    final turma = widget.pairing.turmas[widget.turmaIndice];
    return Scaffold(
      appBar: AppBar(title: Text(turma.nome)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _dialogoAluno(),
        icon: const Icon(Icons.person_add),
        label: const Text('Novo aluno'),
      ),
      body: turma.alunos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum aluno nesta turma ainda.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: turma.alunos.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final aluno = turma.alunos[i];
                return Dismissible(
                  key: ValueKey('aluno|$aluno'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  onDismissed: (_) =>
                      widget.pairing.removerAluno(widget.turmaIndice, i),
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(aluno),
                    onTap: () => _dialogoAluno(indice: i),
                  ),
                );
              },
            ),
    );
  }
}
