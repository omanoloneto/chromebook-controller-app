// Chamada da aula: a lista da turma; tocar num aluno marca a presença e já
// pergunta em qual unidade ele sentou. Abre sozinha ao iniciar a aula e pelo
// botão Chamada da aula, para quem chega depois.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pairing/chamada.dart';
import '../pairing/pairing_controller.dart';
import 'componentes.dart';

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
      final trocar = await confirmar(
        context,
        titulo: 'Unidade $numero ocupada',
        mensagem: 'A unidade $numero está com $ocupante. Pôr $aluno no lugar? '
            '$ocupante fica sem PC até você marcar outra unidade.',
        acao: 'Trocar',
      );
      if (!trocar || !mounted) return;
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
              title: Text(aluno, style: Theme.of(ctx).textTheme.titleMedium),
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
            const SizedBox(height: 8),
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
    final nome = await pedirTexto(
      context,
      titulo: 'Aluno novo',
      rotulo: 'Nome do aluno',
      dica: 'ex.: William',
      acao: 'Cadastrar',
      capitalizacao: TextCapitalization.words,
    );
    if (nome == null || !mounted) return;
    final erro = await _pairing.cadastrarAlunoNaAula(nome);
    if (!mounted) return;
    if (erro != null) {
      _snack(erro);
      return;
    }
    await _perguntarUnidade(nome);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final alunos = _pairing.alunosDaAula;
    final presentes = alunos.where((a) => _pairing.pcDoAluno(a) != null).length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chamada'),
            const SizedBox(height: 2),
            Text(_pairing.turmaDaAula, style: t.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _alunoNovo,
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Aluno novo',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: alunos.isEmpty
          ? EstadoVazio(
              icone: Icons.groups_outlined,
              titulo: 'Nenhum aluno nesta turma ainda.',
              texto: 'Cadastre quem chegou; o nome fica na turma para as '
                  'próximas aulas.',
              acao: FilledButton.icon(
                onPressed: _alunoNovo,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Cadastrar aluno'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                _resumo(presentes, alunos.length),
                const SizedBox(height: 12),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (var i = 0; i < alunos.length; i++) ...[
                        if (i > 0) const Divider(indent: 68),
                        _linha(alunos[i]),
                      ],
                    ],
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

  Widget _resumo(int presentes, int total) {
    final t = Theme.of(context);
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$presentes de $total presentes', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: total == 0 ? 0 : presentes / total,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Toque no aluno que chegou e diga em qual unidade ele sentou.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _linha(String aluno) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final deviceId = _pairing.pcDoAluno(aluno);
    final presente = deviceId != null;
    final unidade = _unidadeDe(aluno);
    return InkWell(
      onTap: () => _tocar(aluno),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: presente ? s.primary : s.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: presente
                  ? Icon(Icons.check, size: 20, color: s.onPrimary)
                  : Text(
                      aluno.characters.first.toUpperCase(),
                      style: t.textTheme.labelLarge?.copyWith(color: s.onSurfaceVariant),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aluno,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(fontSize: 15),
                  ),
                  if (presente)
                    Text(
                      unidade == null ? _pairing.nomeDoPc(deviceId) : 'Unidade $unidade',
                      style: t.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (!presente)
              Text(
                'Marcar',
                style: t.textTheme.labelLarge?.copyWith(color: s.primary),
              ),
          ],
        ),
      ),
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
