// Chamada da aula: a lista da turma; tocar num aluno marca a presença e já
// pergunta em qual unidade ele sentou. Abre sozinha ao iniciar a aula e pela
// faixa da aula, para quem chega depois.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pairing/chamada.dart';
import '../pairing/pairing_controller.dart';

Route<void> rotaChamada(PairingController pairing) =>
    MaterialPageRoute(builder: (_) => ChamadaPage(pairing: pairing));

class ChamadaPage extends StatefulWidget {
  const ChamadaPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<ChamadaPage> createState() => _ChamadaPageState();
}

class _ChamadaPageState extends State<ChamadaPage> {
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

  void _snack(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  int? _unidadeDe(String aluno) {
    final id = _pairing.pcDoAluno(aluno);
    return id == null ? null : _pairing.numeroDe(id);
  }

  Future<void> _tocar(String aluno) async {
    if (_pairing.pcDoAluno(aluno) == null) {
      await _perguntarUnidade(aluno);
    } else {
      await _opcoesDoPresente(aluno);
    }
  }

  Future<void> _perguntarUnidade(String aluno) async {
    final numero = await showDialog<int>(
      context: context,
      builder: (_) => DialogoUnidade(
        pairing: _pairing,
        aluno: aluno,
        atual: _unidadeDe(aluno),
      ),
    );
    if (numero == null || !mounted) return;
    final deviceId = _pairing.pcDaUnidade(numero);
    final ocupante = deviceId == null ? null : _pairing.alunoDe(deviceId);
    if (ocupante != null && ocupante != aluno) {
      final trocar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Unidade $numero ocupada'),
          content: Text(
            'A unidade $numero está com $ocupante. Pôr $aluno no lugar? '
            '$ocupante fica sem PC até você marcar outra unidade.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Trocar'),
            ),
          ],
        ),
      );
      if (trocar != true || !mounted) return;
    }
    final erro = await _pairing.marcarPresente(aluno, numero);
    if (erro != null && mounted) _snack(erro);
  }

  Future<void> _opcoesDoPresente(String aluno) async {
    final unidade = _unidadeDe(aluno);
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(aluno),
              subtitle: Text(
                unidade == null ? 'Presente' : 'Presente na unidade $unidade',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Trocar de unidade'),
              onTap: () => Navigator.pop(ctx, 'trocar'),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Marcar falta'),
              onTap: () => Navigator.pop(ctx, 'falta'),
            ),
          ],
        ),
      ),
    );
    if (escolha == 'trocar') {
      await _perguntarUnidade(aluno);
    } else if (escolha == 'falta') {
      await _pairing.marcarFalta(aluno);
    }
  }

  Future<void> _alunoNovo() async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aluno novo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome do aluno',
            hintText: 'ex.: William',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Cadastrar'),
          ),
        ],
      ),
    );
    if (nome == null || !mounted) return;
    final erro = await _pairing.cadastrarAlunoNaAula(nome);
    if (!mounted) return;
    if (erro != null) {
      _snack(erro);
      return;
    }
    await _perguntarUnidade(nome.trim());
  }

  @override
  Widget build(BuildContext context) {
    final alunos = _pairing.alunosDaAula;
    final presentes = alunos.where((a) => _pairing.pcDoAluno(a) != null).length;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Chamada · ${_pairing.turmaDaAula}'),
        actions: [
          IconButton(
            onPressed: _alunoNovo,
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Aluno novo',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$presentes de ${alunos.length} presentes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'Toque no aluno que veio',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: alunos.isEmpty ? 0 : presentes / alunos.length,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: alunos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Nenhum aluno nesta turma ainda.'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _alunoNovo,
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Cadastrar aluno'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: alunos.length,
                    itemBuilder: (_, i) => _linha(alunos[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Concluir chamada'),
          ),
        ),
      ),
    );
  }

  Widget _linha(String aluno) {
    final scheme = Theme.of(context).colorScheme;
    final deviceId = _pairing.pcDoAluno(aluno);
    final presente = deviceId != null;
    final unidade = _unidadeDe(aluno);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            presente ? scheme.primary : scheme.surfaceContainerHighest,
        foregroundColor: presente ? scheme.onPrimary : scheme.onSurfaceVariant,
        child: presente
            ? const Icon(Icons.check)
            : Text(aluno.characters.first.toUpperCase()),
      ),
      title: Text(aluno),
      subtitle: presente
          ? Text(
              unidade == null ? _pairing.nomeDoPc(deviceId) : 'Unidade $unidade',
            )
          : null,
      trailing: presente
          ? null
          : Text('Marcar', style: TextStyle(color: scheme.primary)),
      onTap: () => _tocar(aluno),
    );
  }
}

/// Pergunta em qual unidade o aluno sentou: o número digitado ou um dos
/// atalhos das unidades ligadas e livres. Devolve o número já conferido.
class DialogoUnidade extends StatefulWidget {
  const DialogoUnidade({
    super.key,
    required this.pairing,
    required this.aluno,
    this.atual,
  });

  final PairingController pairing;
  final String aluno;
  final int? atual;

  @override
  State<DialogoUnidade> createState() => _DialogoUnidadeState();
}

class _DialogoUnidadeState extends State<DialogoUnidade> {
  late final _ctrl = TextEditingController(text: widget.atual?.toString() ?? '');
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar(String texto) {
    final numero = int.tryParse(texto.trim());
    final deviceId = numero == null ? null : widget.pairing.pcDaUnidade(numero);
    final motivo = motivoContraUnidade(
      numero,
      deviceId: deviceId,
      ehTelao: deviceId != null && widget.pairing.ehPcProfessor(deviceId),
    );
    if (motivo != null) {
      setState(() => _erro = motivo);
      return;
    }
    Navigator.pop(context, numero);
  }

  @override
  Widget build(BuildContext context) {
    final livres = widget.pairing.unidadesLivres;
    return AlertDialog(
      title: Text('Unidade de ${widget.aluno}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Número da unidade',
                hintText: 'Ex.: 7',
                errorText: _erro,
              ),
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              onSubmitted: _confirmar,
            ),
            if (livres.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Ligadas e livres',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in livres)
                    ActionChip(
                      label: Text('$n'),
                      onPressed: () => _confirmar('$n'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => _confirmar(_ctrl.text),
          child: const Text('Presente'),
        ),
      ],
    );
  }
}
