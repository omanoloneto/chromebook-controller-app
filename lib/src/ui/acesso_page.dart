// Telas do portão de entrada: entrar com Google, esperar a liberação da
// escola e a espera enquanto o app confere.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'componentes.dart';

class TelaDeEntrar extends StatefulWidget {
  const TelaDeEntrar({super.key, required this.onEntrar});

  final Future<void> Function() onEntrar;

  @override
  State<TelaDeEntrar> createState() => _TelaDeEntrarState();
}

class _TelaDeEntrarState extends State<TelaDeEntrar> {
  bool _entrando = false;

  Future<void> _entrar() async {
    setState(() => _entrando = true);
    try {
      await widget.onEntrar();
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EstadoVazio(
          icone: Icons.school_outlined,
          titulo: 'Controle de Aula',
          texto: 'Entre com a conta Google que a coordenação da escola liberou para você.',
          acao: FilledButton.icon(
            onPressed: _entrando ? null : _entrar,
            icon: _entrando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Entrar com Google'),
          ),
        ),
      ),
    );
  }
}

class TelaSemVinculo extends StatelessWidget {
  const TelaSemVinculo({super.key, required this.email, required this.onOutraConta});

  final String? email;
  final Future<void> Function() onOutraConta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = email;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - 48),
            child: EstadoVazio(
              icone: Icons.lock_clock_outlined,
              titulo: 'Sua conta ainda não tem vínculo com a escola',
              texto: 'Peça ao administrador da sua escola para liberar o seu cadastro. '
                  'Assim que ele liberar, o app abre sozinho.',
              acao: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e != null) ...[
                    Text('Informe este e-mail:', style: t.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    SelectableText(
                      e,
                      key: const ValueKey('email-sem-vinculo'),
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: e));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('E-mail copiado.')));
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar e-mail'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Flexible(child: Text('Esperando a liberação…')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: onOutraConta, child: const Text('Usar outra conta')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TelaDeEspera extends StatelessWidget {
  const TelaDeEspera({super.key, this.texto, this.onTentarDeNovo});

  final String? texto;
  final VoidCallback? onTentarDeNovo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onTentarDeNovo == null) const CircularProgressIndicator(),
              if (texto != null) ...[
                const SizedBox(height: 16),
                Text(texto!, textAlign: TextAlign.center),
              ],
              if (onTentarDeNovo != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onTentarDeNovo, child: const Text('Tentar de novo')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
