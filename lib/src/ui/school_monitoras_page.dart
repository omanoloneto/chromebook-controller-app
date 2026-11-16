// Ajustes → Monitoras da escola (só o fundador): quem entra no modo monitora,
// que só ajuda na sala e cuida do carrinho (sem câmera, fotos ou bloqueios).

import 'package:flutter/material.dart';

import '../cloud/monitoras.dart';
import '../cloud/school_members.dart';
import '../platform/host.dart';
import 'componentes.dart';

class SchoolMonitorasPage extends StatefulWidget {
  const SchoolMonitorasPage({super.key});

  @override
  State<SchoolMonitorasPage> createState() => _SchoolMonitorasPageState();
}

class _SchoolMonitorasPageState extends State<SchoolMonitorasPage> {
  final SchoolMonitoras _members = SchoolMonitoras();
  late final Stream<List<String>> _emails = _members.emails();

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _adicionar() async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liberar uma monitora'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'E-mail da conta Google',
            hintText: 'ex.: ana.silva@gmail.com',
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
            child: const Text('Liberar'),
          ),
        ],
      ),
    );
    if (email == null || !mounted) return;
    try {
      final erro = await _members.adicionar(email);
      if (erro == null) await _members.publicarNosPcs();
      _snack(erro ?? 'Pronto! ${normalizarEmail(email)} já pode entrar como monitora.');
    } catch (_) {
      _snack('Não deu para salvar. Confira a internet $ofThisDeviceText.');
    }
  }

  Future<void> _remover(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar o acesso'),
        content: Text(
          'Tirar o acesso de monitora de $email?\n\n'
          'Ela deixa de ver e de comandar os computadores na hora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tirar o acesso'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _members.remover(email);
      _snack('$email não é mais monitora.');
    } catch (_) {
      _snack('Não deu para salvar. Confira a internet $ofThisDeviceText.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final apagado = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Monitoras da escola')),
      body: StreamBuilder<List<String>>(
        stream: _emails,
        builder: (context, snap) {
          final emails = snap.data ?? const <String>[];
          return ListView(
            padding: recuoDaLista(context),
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Liberar uma monitora'),
                subtitle: const Text('Pelo e-mail da conta Google dela'),
                onTap: _adicionar,
              ),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('O que a monitora pode fazer'),
                subtitle: Text(
                  'Ver a tela, mandar mensagem, fechar abas, sair da conta, '
                  'reiniciar, desligar e ver a bateria. Não vê câmera, fotos nem '
                  'histórico, e não mexe em bloqueios nem na escola.',
                ),
              ),
              if (snap.hasError)
                ListTile(
                  title: Text('Não deu para carregar. Confira a internet $ofThisDeviceText.'),
                )
              else if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (emails.isEmpty)
                ListTile(
                  title: Text(
                    'Nenhuma monitora liberada ainda.',
                    style: TextStyle(color: apagado),
                  ),
                ),
              for (final email in emails)
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: Text(email),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Tirar o acesso',
                    onPressed: () => _remover(email),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
