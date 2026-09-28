// Ajustes → Professores da escola (só o fundador): quem pode entrar na escola.

import 'package:flutter/material.dart';

import '../cloud/school_members.dart';

class SchoolMembersPage extends StatefulWidget {
  const SchoolMembersPage({super.key, this.emailFundador});

  final String? emailFundador;

  @override
  State<SchoolMembersPage> createState() => _SchoolMembersPageState();
}

class _SchoolMembersPageState extends State<SchoolMembersPage> {
  final SchoolMembers _members = SchoolMembers();
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
        title: const Text('Liberar um professor'),
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
      _snack(erro ?? 'Pronto! ${normalizarEmail(email)} já pode entrar na escola.');
    } catch (_) {
      _snack('Não deu para salvar. Confira a internet do celular.');
    }
  }

  Future<void> _remover(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar da escola'),
        content: Text(
          'Tirar $email da escola?\n\n'
          'Essa pessoa deixa de ver os PCs, as turmas e as regras da escola '
          'no app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tirar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _members.remover(email);
      _snack('$email saiu da escola.');
    } catch (_) {
      _snack('Não deu para salvar. Confira a internet do celular.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final apagado = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Professores da escola')),
      body: StreamBuilder<List<String>>(
        stream: _emails,
        builder: (context, snap) {
          final emails = snap.data ?? const <String>[];
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Liberar um professor'),
                subtitle: const Text('Pelo e-mail da conta Google dele'),
                onTap: _adicionar,
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(widget.emailFundador ?? 'Você'),
                subtitle: const Text('Criou a escola: sempre tem acesso'),
              ),
              if (snap.hasError)
                const ListTile(
                  title: Text('Não deu para carregar. Confira a internet do celular.'),
                )
              else if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (emails.isEmpty)
                ListTile(
                  title: Text(
                    'Nenhum professor liberado ainda.',
                    style: TextStyle(color: apagado),
                  ),
                ),
              for (final email in emails)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(email),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Tirar da escola',
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
