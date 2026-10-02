// "Olhos em mim" (item 24): o sheet de travar as telas da turma em 2 toques
// (tocar num texto pronto já trava a aula toda), o texto personalizado, o
// "Silenciar o som" (ligado por padrão) e o "Escolher computadores". E os
// chips da lista de PCs: "Tela travada" e "Travada sem professor".
// Ver SPEC-turma §7.4.

import 'package:flutter/material.dart';

import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import '../util/natural_sort.dart';
import 'theme.dart';

/// Textos prontos, nesta ordem (o primeiro é o padrão).
const List<String> kTextosDaTrava = [
  'Olhos no professor',
  'Atenção à explicação',
];

/// O que o professor escolheu no sheet.
class PedidoDeTrava {
  const PedidoDeTrava({required this.texto, required this.mute, this.apenas});

  final String texto;
  final bool mute;

  /// "Escolher computadores": só estes; null = a aula toda.
  final Set<String>? apenas;
}

String rotuloTravarN(int n) =>
    n == 1 ? 'Travar 1 computador' : 'Travar $n computadores';

/// Toque em "Olhos em mim": abre o sheet e trava. Erro vira SnackBar; o
/// sucesso aparece na faixa ("Travando… 3 de 20").
Future<void> travarComSheet(
  BuildContext context,
  PairingController pairing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final sem = pairing.motivoSemTurma;
  if (sem != null) {
    snack(sem);
    return;
  }
  final pedido = await showModalBottomSheet<PedidoDeTrava>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SheetTrava(pairing: pairing),
  );
  if (pedido == null) return;
  final erro = await pairing.travarTurma(
    texto: pedido.texto,
    mute: pedido.mute,
    apenas: pedido.apenas,
  );
  if (erro != null) snack(erro);
}

/// Toque em "Destravar": um toque destrava todos os PCs com a tela travada.
Future<void> destravarTurma(
  BuildContext context,
  PairingController pairing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final erro = await pairing.destravarTurma();
  if (erro != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(erro)));
  }
}

class SheetTrava extends StatefulWidget {
  const SheetTrava({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<SheetTrava> createState() => _SheetTravaState();
}

class _SheetTravaState extends State<SheetTrava> {
  PairingController get _p => widget.pairing;

  bool _mute = true;
  bool _personalizado = false;
  bool _escolher = false;
  final _texto = TextEditingController();
  final Set<String> _escolhidos = {};

  @override
  void initState() {
    super.initState();
    _texto.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _travar(String texto, {Set<String>? apenas}) {
    final t = texto.trim();
    Navigator.pop(
      context,
      PedidoDeTrava(
        texto: t.isEmpty ? kTextosDaTrava.first : t,
        mute: _mute,
        apenas: apenas,
      ),
    );
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
            child: _escolher ? _escolherComputadores() : _principal(),
          ),
        ),
      ),
    );
  }

  Widget _principal() {
    final scheme = Theme.of(context).colorScheme;
    final n = _p.pcsDaTurma.length;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          'Travar as telas da turma',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          n == 1
              ? 'O computador com aluno nesta aula mostra a mensagem em tela cheia até você destravar.'
              : 'Os $n computadores com aluno nesta aula mostram a mensagem em tela cheia até você destravar.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final (i, texto) in kTextosDaTrava.indexed) ...[
          _OpcaoDeTrava(
            icone: i == 0
                ? Icons.visibility_outlined
                : Icons.record_voice_over_outlined,
            texto: texto,
            destaque: i == 0,
            onTap: () => _travar(texto),
          ),
          const SizedBox(height: 8),
        ],
        if (!_personalizado)
          _OpcaoDeTrava(
            icone: Icons.edit_outlined,
            texto: 'Texto personalizado…',
            mostrarCadeado: false,
            onTap: () => setState(() => _personalizado = true),
          )
        else ...[
          TextField(
            controller: _texto,
            autofocus: true,
            maxLength: kMaxTravaTexto,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Mensagem na tela dos alunos',
              hintText: 'Ex.: Guardem o material e olhem para a lousa.',
            ),
          ),
          FilledButton.icon(
            onPressed:
                _texto.text.trim().isEmpty ? null : () => _travar(_texto.text),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Travar'),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.volume_off_outlined),
          title: const Text('Silenciar o som'),
          value: _mute,
          onChanged: (v) => setState(() => _mute = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _escolher = true),
            icon: const Icon(Icons.checklist),
            label: const Text('Escolher computadores'),
          ),
        ),
      ],
    );
  }

  Widget _escolherComputadores() {
    final scheme = Theme.of(context).colorScheme;
    final ids = [..._p.pcsDaTurma]
      ..sort((a, b) => compararNatural(_p.nomeDoPc(a), _p.nomeDoPc(b)));
    final n = _escolhidos.length;
    final texto =
        _texto.text.trim().isEmpty ? kTextosDaTrava.first : _texto.text;
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
                onPressed: () => setState(() => _escolher = false),
              ),
              Expanded(
                child: Text(
                  'Escolher computadores',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final id in ids)
                CheckboxListTile(
                  value: _escolhidos.contains(id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _escolhidos.add(id);
                    } else {
                      _escolhidos.remove(id);
                    }
                  }),
                  title: Text(_p.nomeDoPc(id)),
                  subtitle: Text(
                    _online(id) ? 'online' : 'desligado — trava quando ligar',
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Mensagem: $texto',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.volume_off_outlined),
                title: const Text('Silenciar o som'),
                value: _mute,
                onChanged: (v) => setState(() => _mute = v),
              ),
              FilledButton.icon(
                onPressed: n == 0
                    ? null
                    : () => _travar(texto, apenas: {..._escolhidos}),
                icon: const Icon(Icons.lock_outline),
                label: Text(rotuloTravarN(n)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _online(String id) {
    final s = _p.pcPorId(id);
    return s != null && _p.isOnline(s);
  }
}

class _OpcaoDeTrava extends StatelessWidget {
  const _OpcaoDeTrava({
    required this.icone,
    required this.texto,
    required this.onTap,
    this.destaque = false,
    this.mostrarCadeado = true,
  });

  final IconData icone;
  final String texto;
  final VoidCallback onTap;
  final bool destaque;
  final bool mostrarCadeado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fundo =
        destaque ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final frente = destaque ? scheme.onPrimaryContainer : scheme.onSurface;
    return Material(
      color: fundo,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icone, color: frente),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  texto,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: frente,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (mostrarCadeado)
                Icon(Icons.lock_outline, size: 20, color: frente),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Chips da lista de PCs ---------------------------------------------------------

/// Chip pequeno da linha do PC ("Tela travada", "Mão levantada"…).
class ChipDoPc extends StatelessWidget {
  const ChipDoPc({
    super.key,
    required this.icone,
    required this.texto,
    required this.fundo,
    required this.frente,
    this.onTap,
  });

  final IconData icone;
  final String texto;
  final Color fundo;
  final Color frente;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fundo,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 14, color: frente),
              const SizedBox(width: 4),
              Text(
                texto,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: frente,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips de trava de um PC: "Tela travada", ou "Travada sem professor" com o
/// botão "Destravar" (qualquer professor da escola pode destravar). Vazio se
/// a tela não está travada.
List<Widget> chipsDeTrava(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) {
  if (!pairing.telaTravada(deviceId)) return const [];
  final scheme = Theme.of(context).colorScheme;
  final c = cores(context);
  if (pairing.travadaSemProfessor(deviceId)) {
    return [
      ChipDoPc(
        icone: Icons.lock_clock,
        texto: 'Travada sem professor',
        fundo: c.atencao.withValues(alpha: 0.16),
        frente: c.atencao,
      ),
      ChipDoPc(
        icone: Icons.lock_open,
        texto: 'Destravar',
        fundo: scheme.primary,
        frente: scheme.onPrimary,
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final erro = await pairing.destravarPc(deviceId);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(erro ?? 'Destravando…')));
        },
      ),
    ];
  }
  return [
    ChipDoPc(
      icone: Icons.lock,
      texto: 'Tela travada',
      fundo: scheme.primaryContainer,
      frente: scheme.onPrimaryContainer,
    ),
  ];
}
