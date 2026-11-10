// Chamada da aula: a lista da turma; tocar num aluno marca a presença, com
// ou sem computador (número da unidade, um PC da lista ou nenhum). Abre
// sozinha ao iniciar a aula e pelo botão Chamada da aula, para quem chega
// depois.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pairing/chamada.dart';
import '../pairing/pairing_controller.dart';
import '../platform/host.dart';
import '../util/natural_sort.dart';
import 'componentes.dart';
import 'layout.dart';

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

  /// Onde o aluno está: "Unidade 7", o nome do PC ou "Sem computador".
  String _ondeEsta(String aluno) {
    final id = _pairing.pcDoAluno(aluno);
    if (id == null) return 'Sem computador';
    final n = _pairing.numeroDe(id);
    if (n != null) return 'Unidade $n';
    final s = _pairing.pcPorId(id);
    return s == null ? 'Computador' : _pairing.nomeDe(s);
  }

  Future<void> _tocar(String aluno) async {
    if (_pairing.alunoPresente(aluno)) {
      await _opcoesDoPresente(aluno);
    } else {
      await _escolherPresenca(aluno);
    }
  }

  Future<void> _escolherPresenca(String aluno) async {
    final escolha = await showModalBottomSheet<EscolhaPresenca>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SheetPresenca(
        pairing: _pairing,
        aluno: aluno,
        atual: _unidadeDe(aluno),
      ),
    );
    if (escolha == null || !mounted) return;
    final String? erro;
    switch (escolha) {
      case PresencaSemPc():
        erro = await _pairing.marcarPresenteSemPc(aluno);
      case PresencaNaUnidade(:final numero):
        final deviceId = _pairing.pcDaUnidade(numero);
        if (!await _confirmarTroca(aluno, deviceId, 'A unidade $numero')) return;
        erro = await _pairing.marcarPresente(aluno, numero);
      case PresencaNoPc(:final deviceId):
        final s = _pairing.pcPorId(deviceId);
        final nome = s == null ? 'Esse PC' : _pairing.nomeDe(s);
        if (!await _confirmarTroca(aluno, deviceId, nome)) return;
        erro = await _pairing.marcarPresenteNoPc(aluno, deviceId);
    }
    if (erro != null && mounted) _snack(erro);
  }

  /// PC com outro aluno: confirma antes de pôr [aluno] no lugar.
  Future<bool> _confirmarTroca(String aluno, String? deviceId, String pc) async {
    final ocupante = deviceId == null ? null : _pairing.alunoDe(deviceId);
    if (ocupante == null || ocupante == aluno || !mounted) return true;
    final trocar = await confirmar(
      context,
      titulo: 'Computador ocupado',
      mensagem: '$pc está com $ocupante. Pôr $aluno no lugar? '
          '$ocupante continua presente, mas sem computador.',
      acao: 'Trocar',
    );
    return trocar && mounted;
  }

  Future<void> _opcoesDoPresente(String aluno) async {
    final temPc = _pairing.pcDoAluno(aluno) != null;
    final onde = _ondeEsta(aluno);
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(aluno, style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(temPc ? 'Presente · $onde' : 'Presente, sem computador'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(temPc ? Icons.swap_horiz : Icons.computer_outlined),
              title: Text(temPc ? 'Trocar de computador' : 'Pôr num computador'),
              onTap: () => Navigator.pop(ctx, 'pc'),
            ),
            if (temPc)
              ListTile(
                leading: const Icon(Icons.no_cell_outlined),
                title: const Text('Tirar do computador'),
                subtitle: const Text('Continua presente'),
                onTap: () => Navigator.pop(ctx, 'tirar'),
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
    if (!mounted) return;
    switch (escolha) {
      case 'pc':
        await _escolherPresenca(aluno);
      case 'tirar':
        await _pairing.tirarDoPc(aluno);
      case 'falta':
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
    await _escolherPresenca(nome);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final alunos = _pairing.alunosDaAula;
    final presentes = alunos.where(_pairing.alunoPresente).length;
    final lateral = contentSideMargin(context);
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
              padding: recuoDaLista(context, topo: 4),
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
          padding: EdgeInsets.fromLTRB(16 + lateral, 8, 16 + lateral, 12),
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
            'Toque no aluno que chegou. Dá para dizer em qual computador ele '
            'sentou ou marcar presença sem computador.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _linha(String aluno) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final presente = _pairing.alunoPresente(aluno);
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
                  if (presente) Text(_ondeEsta(aluno), style: t.textTheme.bodySmall),
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

/// Folha de presença de um aluno: o número da unidade (digitado ou um dos
/// atalhos das ligadas e livres), um PC escolhido na lista completa, ou
/// presente sem computador. Devolve a [EscolhaPresenca].
class SheetPresenca extends StatefulWidget {
  const SheetPresenca({
    super.key,
    required this.pairing,
    required this.aluno,
    this.atual,
  });

  final PairingController pairing;
  final String aluno;
  final int? atual;

  @override
  State<SheetPresenca> createState() => _SheetPresencaState();
}

class _SheetPresencaState extends State<SheetPresenca> {
  late final _ctrl = TextEditingController(text: widget.atual?.toString() ?? '');
  String? _erro;
  bool _lista = false;

  PairingController get _p => widget.pairing;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmarUnidade(String texto) {
    final numero = int.tryParse(texto.trim());
    final deviceId = numero == null ? null : _p.pcDaUnidade(numero);
    final motivo = motivoContraUnidade(
      numero,
      deviceId: deviceId,
      ehTelao: deviceId != null && _p.ehPcProfessor(deviceId),
    );
    if (motivo != null) {
      setState(() => _erro = motivo);
      return;
    }
    Navigator.pop(context, PresencaNaUnidade(numero!));
  }

  @override
  Widget build(BuildContext context) {
    final altura = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: altura),
        child: SafeArea(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _lista ? _escolherPc() : _principal(),
          ),
        ),
      ),
    );
  }

  Widget _principal() {
    final t = Theme.of(context).textTheme;
    final livres = _p.unidadesLivres;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text('Presença de ${widget.aluno}', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Em qual computador ${widget.aluno} sentou?',
          style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
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
                onChanged: (_) => setState(() => _erro = null),
                onSubmitted: _confirmarUnidade,
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton(
                onPressed: () => _confirmarUnidade(_ctrl.text),
                child: const Text('Presente'),
              ),
            ),
          ],
        ),
        if (livres.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Ligadas e livres', style: t.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in livres)
                ActionChip(
                  label: Text('$n'),
                  onPressed: () => _confirmarUnidade('$n'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _lista = true),
          icon: const Icon(Icons.computer_outlined),
          label: const Text('Escolher o computador na lista'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, const PresencaSemPc()),
          icon: const Icon(Icons.how_to_reg_outlined),
          label: const Text('Presente sem computador'),
        ),
      ],
    );
  }

  /// Situação de um PC na lista: null quando pode receber o aluno.
  ({String texto, bool pode}) _situacao(String deviceId) {
    final motivo = motivoContraPc(
      conectado: true,
      ehTelao: _p.ehPcProfessor(deviceId),
      aulaDeOutro: _p.professorQueTravou(deviceId),
    );
    if (motivo != null) return (texto: motivo, pode: false);
    final aluno = _p.alunoDe(deviceId);
    if (aluno != null) return (texto: 'Com $aluno', pode: true);
    final s = _p.pcPorId(deviceId);
    final ligado = s != null && _p.isOnline(s);
    return (texto: ligado ? 'Ligado e livre' : 'Desligado · vale assim mesmo', pode: true);
  }

  Widget _escolherPc() {
    final t = Theme.of(context);
    final pcs = [..._p.pcs]..sort((a, b) => compararNatural(_p.nomeDe(a), _p.nomeDe(b)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _lista = false),
              ),
              Expanded(
                child: Text('Computador de ${widget.aluno}', style: t.textTheme.titleLarge),
              ),
            ],
          ),
        ),
        if (pcs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              onComputer
                  ? 'Nenhum computador conectado. Conecte pelo app no celular '
                      'ou marque a presença sem computador.'
                  : 'Nenhum computador conectado a este celular. Conecte pelo QR '
                      '(Aula › ⋮ › Conectar computador) ou marque a presença sem '
                      'computador.',
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final s in pcs)
                  Builder(builder: (context) {
                    final n = _p.numeroDe(s.deviceId);
                    final nome = _p.nomeDe(s);
                    // PC chamado "Unidade 7" com o número 7: uma vez só.
                    final titulo = n == null || nome == 'Unidade $n' ? nome : 'Unidade $n · $nome';
                    final situacao = _situacao(s.deviceId);
                    final apagado = !_p.isOnline(s) || !situacao.pode;
                    return ListTile(
                      enabled: situacao.pode,
                      leading: Icon(
                        Icons.computer_outlined,
                        color: apagado ? t.colorScheme.onSurfaceVariant : t.colorScheme.primary,
                      ),
                      title: Text(titulo),
                      subtitle: Text(situacao.texto),
                      onTap: () => Navigator.pop(context, PresencaNoPc(s.deviceId)),
                    );
                  },),
              ],
            ),
          ),
      ],
    );
  }
}
