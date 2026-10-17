// Energia dos PCs com Celita OS: encerrar a sessão, reiniciar e desligar, num
// PC (menu ⋮ da tela dele) ou na turma (ícone de desligar no banner da aula).
// Sempre com confirmação: o PC age na hora, sem contagem na tela do aluno. A
// faixa de entrega mostra quem recebeu.

import 'package:flutter/material.dart';

import '../commands/command.dart';
import '../pairing/pairing_controller.dart';

/// Rótulo e ícone de cada ação (menu do PC e sheet da turma).
extension TextosDeEnergia on AcaoEnergia {
  String get rotulo => switch (this) {
        AcaoEnergia.encerrar => 'Encerrar a sessão',
        AcaoEnergia.reiniciar => 'Reiniciar',
        AcaoEnergia.desligar => 'Desligar',
      };

  IconData get icone => switch (this) {
        AcaoEnergia.encerrar => Icons.logout,
        AcaoEnergia.reiniciar => Icons.restart_alt,
        AcaoEnergia.desligar => Icons.power_settings_new,
      };

  String get _efeito => switch (this) {
        AcaoEnergia.encerrar => 'Sai da conta aberta; o computador continua ligado',
        AcaoEnergia.reiniciar => 'Desliga e liga de novo',
        AcaoEnergia.desligar => 'Fica desligado até alguém ligar',
      };

  String get _botao => this == AcaoEnergia.encerrar ? 'Encerrar' : rotulo;

  String _perguntaPc(String nome) => this == AcaoEnergia.encerrar
      ? 'Encerrar a sessão de $nome?'
      : '$rotulo $nome?';

  String _perguntaTurma(int n) => switch (this) {
        AcaoEnergia.encerrar => n == 1
            ? 'Encerrar a sessão de 1 computador?'
            : 'Encerrar as sessões de $n computadores?',
        _ => n == 1 ? '$rotulo 1 computador?' : '$rotulo $n computadores?',
      };

  String _aviso({required bool varios}) {
    const perde = 'Quem estiver usando perde o que não salvou.';
    final espera = varios
        ? 'Os que estiverem instalando uma atualização terminam antes.'
        : 'Se estiver instalando uma atualização, termina antes.';
    return switch (this) {
      AcaoEnergia.encerrar => varios
          ? 'As contas abertas fecham na hora. $perde'
          : 'A conta aberta fecha na hora. $perde',
      AcaoEnergia.reiniciar =>
        '${varios ? 'Reiniciam' : 'Reinicia'} na hora. $perde $espera',
      AcaoEnergia.desligar =>
        '${varios ? 'Desligam' : 'Desliga'} na hora. $perde $espera',
    };
  }
}

/// Confirma e pede [acao] a um PC (menu ⋮ da tela dele).
Future<void> confirmarEnergiaNoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
  AcaoEnergia acao,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await _confirmar(
    context,
    titulo: acao._perguntaPc(nome),
    aviso: acao._aviso(varios: false),
    botao: acao._botao,
  );
  if (!ok) return;
  final erro = await pairing.energiaNoPc(deviceId, acao);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(erro ?? 'Pedido enviado para $nome.')),
    );
}

/// Toque no ícone de desligar do banner da aula: escolhe a ação, confirma e
/// pede aos PCs da aula que estão ligados com Celita OS.
Future<void> mostrarSheetEnergia(
  BuildContext context,
  PairingController pairing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final sem = pairing.motivoSemEnergia;
  if (sem != null) {
    snack(sem);
    return;
  }
  final n = pairing.pcsParaEnergia.length;
  final onde = pairing.aulaAtiva ? ' nesta aula' : '';
  final acao = await showModalBottomSheet<AcaoEnergia>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Desligar os computadores'),
            subtitle: Text(
              n == 1
                  ? 'Vale para o computador com Celita OS ligado$onde.'
                  : 'Vale para os $n computadores com Celita OS ligados$onde.',
            ),
          ),
          const Divider(height: 1),
          for (final a in AcaoEnergia.values)
            ListTile(
              leading: Icon(a.icone),
              title: Text(a.rotulo),
              subtitle: Text(a._efeito),
              onTap: () => Navigator.pop(ctx, a),
            ),
        ],
      ),
    ),
  );
  if (acao == null || !context.mounted) return;
  final ok = await _confirmar(
    context,
    titulo: acao._perguntaTurma(n),
    aviso: acao._aviso(varios: n > 1),
    botao: acao._botao,
  );
  if (!ok) return;
  final r = await pairing.energiaNaTurma(acao);
  snack(
    r.erro ??
        (r.enviados == 1
            ? 'Pedido enviado para 1 computador.'
            : 'Pedido enviado para ${r.enviados} computadores.'),
  );
}

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String aviso,
  required String botao,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(aviso),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(botao),
        ),
      ],
    ),
  );
  return ok == true;
}
