// Tela de turmas e alunos: cadastro local (nada vai ao Firebase).
// Nível 1 = turmas, cada uma com "Iniciar aula"; toque abre o nível 2 = alunos
// da turma.

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import 'aluno_page.dart';
import 'chamada_page.dart';
import 'componentes.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key, required this.pairing, this.onAulaIniciada});

  final PairingController pairing;

  /// A aula começou por uma turma daqui: a casca volta para a aba Aula.
  final VoidCallback? onAulaIniciada;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  PairingController get _pairing => widget.pairing;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    _pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _dialogoTurma({int? indice}) async {
    final existente = indice != null ? _pairing.turmas[indice] : null;
    final nome = await pedirTexto(
      context,
      titulo: existente == null ? 'Nova turma' : 'Renomear turma',
      rotulo: 'Nome da turma',
      dica: 'ex.: 2º ano A',
      inicial: existente?.nome ?? '',
    );
    if (nome == null) return;
    if (indice == null) {
      await _pairing.adicionarTurma(nome);
    } else {
      await _pairing.renomearTurma(indice, nome);
    }
  }

  Future<void> _removerTurma(int indice) async {
    final t = _pairing.turmas[indice];
    final ok = await confirmar(
      context,
      titulo: 'Remover ${t.nome}',
      mensagem: 'A turma e ${_alunos(t.alunos.length)} saem do app. O histórico '
          'das aulas antigas continua guardado.',
      acao: 'Remover',
      destrutiva: true,
    );
    if (ok) await _pairing.removerTurma(indice);
  }

  // A aula começa pela chamada, como na aba Aula.
  Future<void> _iniciarAula(String turma) async {
    await _pairing.iniciarAula(turma);
    if (!mounted) return;
    widget.onAulaIniciada?.call();
    await Navigator.of(context).push(rotaChamada(_pairing));
  }

  void _abrirTurma(int indice) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _AlunosPage(pairing: _pairing, turmaIndice: indice),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final turmas = _pairing.turmas;
    return Scaffold(
      appBar: AppBar(title: const Text('Turmas')),
      floatingActionButton: FloatingActionButton.extended(
        // Tag única: FABs de abas irmãs ficam montados juntos no IndexedStack.
        heroTag: 'fab_turmas',
        onPressed: () => _dialogoTurma(),
        icon: const Icon(Icons.add),
        label: const Text('Nova turma'),
      ),
      body: turmas.isEmpty
          ? const EstadoVazio(
              icone: Icons.school_outlined,
              titulo: 'Nenhuma turma ainda',
              texto: 'Cadastre suas turmas e alunos para fazer a chamada e '
                  'saber quem está em cada computador durante a aula.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              children: [
                for (var i = 0; i < turmas.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _cartaoDaTurma(i, turmas[i].nome, turmas[i].alunos.length),
                  ),
              ],
            ),
    );
  }

  Widget _cartaoDaTurma(int indice, String nome, int alunos) {
    final t = Theme.of(context);
    final aula = _pairing.aulaAtiva;
    final estaEmAula = aula && _pairing.turmaDaAula == nome;
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      onTap: () => _abrirTurma(indice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, color: t.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome, style: t.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(_alunos(alunos), style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              if (estaEmAula) const Selo('Em aula', icone: Icons.circle, tom: Tom.sucesso),
              PopupMenuButton<String>(
                tooltip: 'Opções da turma',
                onSelected: (v) {
                  if (v == 'renomear') _dialogoTurma(indice: indice);
                  if (v == 'remover') _removerTurma(indice);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'renomear',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Renomear'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remover',
                    // Turma da aula em andamento: só depois de encerrar.
                    enabled: !estaEmAula,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: t.colorScheme.error),
                      title: Text('Remover', style: TextStyle(color: t.colorScheme.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!aula) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _iniciarAula(nome),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar aula'),
            ),
          ],
        ],
      ),
    );
  }
}

String _alunos(int n) => switch (n) {
      0 => 'Nenhum aluno',
      1 => '1 aluno',
      _ => '$n alunos',
    };

// Nível 2: alunos de uma turma.
class _AlunosPage extends StatefulWidget {
  const _AlunosPage({required this.pairing, required this.turmaIndice});

  final PairingController pairing;
  final int turmaIndice;

  @override
  State<_AlunosPage> createState() => _AlunosPageState();
}

class _AlunosPageState extends State<_AlunosPage> {
  PairingController get _pairing => widget.pairing;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    _pairing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _dialogoAluno({int? indice}) async {
    final turma = _pairing.turmas[widget.turmaIndice];
    final existente = indice != null ? turma.alunos[indice] : null;
    final nome = await pedirTexto(
      context,
      titulo: existente == null ? 'Novo aluno' : 'Renomear aluno',
      rotulo: 'Nome do aluno',
      dica: 'ex.: William',
      ajuda: existente == null
          ? null
          : 'O histórico de aulas antigas continua sob o nome anterior.',
      inicial: existente ?? '',
      capitalizacao: TextCapitalization.words,
    );
    if (nome == null) return;
    if (indice == null) {
      await _pairing.adicionarAluno(widget.turmaIndice, nome);
    } else {
      await _pairing.renomearAluno(widget.turmaIndice, indice, nome);
    }
  }

  Future<void> _removerAluno(int indice, String aluno) async {
    final ok = await confirmar(
      context,
      titulo: 'Remover $aluno',
      mensagem: 'O aluno sai da turma. O histórico das aulas antigas continua '
          'guardado.',
      acao: 'Remover',
      destrutiva: true,
    );
    if (ok) await _pairing.removerAluno(widget.turmaIndice, indice);
  }

  @override
  Widget build(BuildContext context) {
    // Turma pode ter sido removida em outra tela.
    if (widget.turmaIndice >= _pairing.turmas.length) {
      return Scaffold(
        appBar: AppBar(),
        body: const EstadoVazio(
          icone: Icons.school_outlined,
          titulo: 'Turma removida',
          texto: 'Esta turma não existe mais.',
        ),
      );
    }
    final t = Theme.of(context);
    final turma = _pairing.turmas[widget.turmaIndice];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(turma.nome),
            const SizedBox(height: 2),
            Text(_alunos(turma.alunos.length), style: t.textTheme.bodySmall),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_alunos',
        onPressed: () => _dialogoAluno(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Novo aluno'),
      ),
      body: turma.alunos.isEmpty
          ? const EstadoVazio(
              icone: Icons.person_add_alt,
              titulo: 'Nenhum aluno nesta turma ainda',
              texto: 'Cadastre aqui ou na chamada, quando o aluno chegar.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              children: [
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (var i = 0; i < turma.alunos.length; i++) ...[
                        if (i > 0) const Divider(indent: 68),
                        _linhaDoAluno(i, turma.alunos[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _linhaDoAluno(int indice, String aluno) {
    final t = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: t.colorScheme.surfaceContainerHighest,
        foregroundColor: t.colorScheme.onSurfaceVariant,
        child: Text(aluno.characters.first.toUpperCase()),
      ),
      title: Text(aluno),
      subtitle: const Text('Ver as aulas'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AlunoPage(pairing: _pairing, aluno: aluno)),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opções do aluno',
        onSelected: (v) {
          if (v == 'renomear') _dialogoAluno(indice: indice);
          if (v == 'remover') _removerAluno(indice, aluno);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'renomear',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('Renomear'),
            ),
          ),
          PopupMenuItem(
            value: 'remover',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: t.colorScheme.error),
              title: Text('Remover', style: TextStyle(color: t.colorScheme.error)),
            ),
          ),
        ],
      ),
    );
  }
}
