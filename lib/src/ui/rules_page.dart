// Tela de regras: bloquear ou alertar por domínio/prefixo de URL.
// Bloqueio vale na hora para todos os PCs; alerta é só no celular.

import 'package:flutter/material.dart';

import '../commands/domain_rules.dart';
import '../pairing/pairing_controller.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
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

  Future<void> _dialogoRegra({int? indice}) async {
    final regras = widget.pairing.regras;
    final existente = indice != null ? regras[indice] : null;
    final ctrl = TextEditingController(text: existente?.pattern ?? '');
    var action = existente?.action ?? RuleAction.block;
    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existente == null ? 'Nova regra' : 'Editar regra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Domínio ou prefixo',
                  hintText: 'ex.: youtube.com ou reddit.com/r/jogos',
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: RuleAction.block,
                    label: Text('Bloquear'),
                    icon: Icon(Icons.block),
                  ),
                  ButtonSegment(
                    value: RuleAction.alert,
                    label: Text('Alertar'),
                    icon: Icon(Icons.warning_amber),
                  ),
                ],
                selected: {action},
                onSelectionChanged: (sel) =>
                    setDialogState(() => action = sel.first),
              ),
            ],
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
      ),
    );
    if (salvo != true || ctrl.text.trim().isEmpty) return;
    if (indice == null) {
      await widget.pairing.adicionarRegra(ctrl.text, action);
    } else {
      await widget.pairing.atualizarRegra(indice, ctrl.text, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regras = widget.pairing.regras;
    return Scaffold(
      appBar: AppBar(title: const Text('Regras de sites')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _dialogoRegra(),
        icon: const Icon(Icons.add),
        label: const Text('Nova regra'),
      ),
      body: Column(
        children: [
          Expanded(
            child: regras.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma regra ainda.\n\n'
                        'Bloquear: o site não abre nos Chromebooks.\n'
                        'Alertar: o cartão do aluno fica vermelho aqui no app.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: regras.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = regras[i];
                      final bloqueia = r.action == RuleAction.block;
                      return Dismissible(
                        key: ValueKey('${r.pattern}|${r.action}|$i'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => widget.pairing.removerRegra(i),
                        child: ListTile(
                          leading: Icon(
                            bloqueia ? Icons.block : Icons.warning_amber,
                            color: bloqueia ? Colors.red : Colors.orange,
                          ),
                          title: Text(r.pattern),
                          subtitle: Text(bloqueia ? 'Bloquear' : 'Alertar'),
                          onTap: () => _dialogoRegra(indice: i),
                        ),
                      );
                    },
                  ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 88),
            child: Text(
              'Domínio (youtube.com) vale para subdomínios (m.youtube.com). '
              'Com "/" vira prefixo (reddit.com/r/jogos). '
              'Alterações valem na hora para todos os PCs conectados.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
