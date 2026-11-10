// Tela de entrada no computador: o QR que o celular do professor lê.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../pairing/computer_login.dart';

class ComputerLoginPage extends StatelessWidget {
  const ComputerLoginPage({super.key, required this.login});

  final ComputerLogin login;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ListenableBuilder(
              listenable: login,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) {
                  final instructions = _Instructions(login: login);
                  final code = _Code(login: login);
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: box.maxWidth >= 640
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(child: instructions),
                              const SizedBox(width: 48),
                              code,
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              instructions,
                              const SizedBox(height: 32),
                              code,
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions({required this.login});

  final ComputerLogin login;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = login.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entrar pelo celular', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        Text(
          'No celular, abra o Controle de Aula, toque em conectar computador '
          'e aponte a câmera para este código. O celular precisa estar com a '
          'conta Google.',
          style: theme.textTheme.bodyLarge,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        switch (login.stage) {
          ComputerLoginStage.failed => FilledButton(
              onPressed: login.start,
              child: const Text('Tentar de novo'),
            ),
          ComputerLoginStage.waiting => const _Status('Aguardando o celular…'),
          ComputerLoginStage.opening => const _Status('Preparando o código…'),
          ComputerLoginStage.entering ||
          ComputerLoginStage.done =>
            const _Status('Entrando…'),
        },
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code({required this.login});

  final ComputerLogin login;

  static const double _side = 280;

  @override
  Widget build(BuildContext context) {
    final payload = login.qrPayload;
    final visible = payload != null && login.stage == ComputerLoginStage.waiting;
    return Container(
      width: _side,
      height: _side,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Branco nos dois temas: a câmera precisa do contraste.
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: visible
          ? QrImageView(data: payload, padding: EdgeInsets.zero)
          : const SizedBox.shrink(),
    );
  }
}
