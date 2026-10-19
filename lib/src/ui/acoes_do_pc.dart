// Ações de um computador, iguais no toque longo da lista e na tela dele: as do
// dia a dia em botões, cada uma a um toque. As raras (renomear, número da
// unidade, telão, atualizar, desconectar) ficam no ⋮ da tela do computador.

import 'package:flutter/material.dart';

import '../cloud/session_registry.dart';
import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import '../util/versao.dart';
import 'chat_page.dart';
import 'componentes.dart';
import 'device_page.dart';
import 'energia_controles.dart';

/// Grade com as ações do dia a dia de um computador. [contexto] é o da tela
/// que fica (a ação roda depois de o sheet fechar); [antes] fecha o sheet.
class AcoesDoPc extends StatelessWidget {
  const AcoesDoPc({
    super.key,
    required this.contexto,
    required this.pairing,
    required this.deviceId,
    this.antes,
    this.onIrParaSites,
  });

  final BuildContext contexto;
  final PairingController pairing;
  final String deviceId;
  final VoidCallback? antes;
  final VoidCallback? onIrParaSites;

  @override
  Widget build(BuildContext context) {
    final s = pairing.pcPorId(deviceId);
    if (s == null) return const SizedBox.shrink();
    final on = pairing.isOnline(s);
    final telao = pairing.ehPcProfessor(deviceId);
    final deOutro = pairing.professorQueTravou(deviceId) != null;
    final celita = temCelita(s.versaoExt);
    final nome = pairing.nomeDoPc(deviceId);
    final aluno = pairing.alunoDe(deviceId);

    VoidCallback? se(bool pode, void Function() acao) => pode
        ? () {
            antes?.call();
            acao();
          }
        : null;

    final acoes = [
      BotaoDeAcao(
        icone: Icons.screenshot_monitor_outlined,
        rotulo: 'Ver tela',
        dica: celita ? 'Ver a tela do computador' : 'Ver a tela: só com Celita OS',
        onPressed: se(
          on && celita,
          () => mostrarImagemDoPc(contexto, pairing, deviceId, nome, tela: true),
        ),
      ),
      BotaoDeAcao(
        icone: Icons.photo_camera_outlined,
        rotulo: 'Foto',
        dica: 'Ver quem está no computador',
        onPressed: se(
          on,
          () => mostrarImagemDoPc(contexto, pairing, deviceId, nome, tela: false),
        ),
      ),
      BotaoDeAcao(
        icone: Icons.open_in_browser,
        rotulo: 'Abrir site',
        dica: 'Abrir um site neste computador',
        onPressed: se(
          on && !deOutro,
          () => mostrarSheetAbrirSite(
            contexto,
            pairing,
            deviceId: deviceId,
            nomePc: nome,
            onEditarFavoritos: onIrParaSites,
          ),
        ),
      ),
      BotaoDeAcao(
        icone: Icons.chat_bubble_outline,
        rotulo: 'Conversar',
        onPressed: se(!telao && !deOutro, () => abrirConversa(contexto, pairing, deviceId)),
      ),
      BotaoDeAcao(
        icone: Icons.lock_open_outlined,
        rotulo: 'Liberar sites',
        dica: 'Liberar sites bloqueados neste computador',
        ligado: !telao && pairing.liberacoesDe(deviceId).isNotEmpty,
        onPressed: se(
          !telao && !deOutro,
          () => mostrarSheetLiberarSites(contexto, pairing, deviceId),
        ),
      ),
      BotaoDeAcao(
        icone: Icons.tab_unselected,
        rotulo: 'Fechar abas',
        dica: 'Fechar todas as abas',
        onPressed: se(on && !deOutro, () => confirmarFecharAbas(contexto, pairing, deviceId)),
      ),
      if (pairing.aulaAtiva && !telao)
        BotaoDeAcao(
          icone: aluno == null ? Icons.person_add_alt : Icons.manage_accounts_outlined,
          rotulo: aluno == null ? 'Aluno' : 'Trocar aluno',
          dica: aluno == null ? 'Escolher o aluno deste computador' : 'Trocar o aluno',
          onPressed: se(!deOutro, () => escolherAlunoDoPc(contexto, pairing, deviceId)),
        ),
      BotaoDeAcao(
        icone: Icons.power_settings_new,
        rotulo: 'Desligar',
        dica: celita ? 'Sair da conta, reiniciar ou desligar' : 'Desligar: só com Celita OS',
        tom: Tom.perigo,
        onPressed: se(
          on && celita && !deOutro,
          () => mostrarEnergiaNoPc(contexto, pairing, deviceId, nome),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GradeDeAcoes(acoes: acoes),
    );
  }
}

/// Toque longo num computador da lista: nome e estado no alto, as ações do
/// dia a dia e o caminho para a tela completa dele.
Future<void> mostrarAcoesDoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId, {
  required VoidCallback onAbrirTela,
  VoidCallback? onIrParaSites,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CabecalhoDoPc(pairing: pairing, deviceId: deviceId),
          const SizedBox(height: 8),
          AcoesDoPc(
            contexto: context,
            pairing: pairing,
            deviceId: deviceId,
            antes: () => Navigator.pop(ctx),
            onIrParaSites: onIrParaSites,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onAbrirTela();
            },
            child: const Text('Abrir a tela do computador'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Número da unidade, nome (aluno ou computador) e a situação numa linha.
class CabecalhoDoPc extends StatelessWidget {
  const CabecalhoDoPc({super.key, required this.pairing, required this.deviceId});

  final PairingController pairing;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final s = pairing.pcPorId(deviceId);
    if (s == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    return ListTile(
      leading: SeloDaUnidade(
        numero: pairing.numeroDe(deviceId),
        estado: estadoDoPc(pairing, s),
      ),
      title: Text(pairing.nomeDoPc(deviceId), style: t.textTheme.titleMedium),
      subtitle: Text(situacaoDoPc(pairing, s)),
    );
  }
}

/// Estado para o número da unidade: telão, alerta de site, ligado ou não.
EstadoDoPc estadoDoPc(PairingController pairing, PcSession s) {
  if (pairing.ehPcProfessor(s.deviceId)) return EstadoDoPc.telao;
  if (!pairing.isOnline(s)) return EstadoDoPc.offline;
  if (s.alerta != null) return EstadoDoPc.alerta;
  return EstadoDoPc.online;
}

/// "Unidade 3 · Ligado" / "Computador do Professor" / "Desligado", para os
/// cabeçalhos (o nome em cima já diz quem é).
String situacaoDoPc(PairingController pairing, PcSession s) {
  final on = pairing.isOnline(s);
  if (pairing.ehPcProfessor(s.deviceId)) {
    return on ? 'Computador do Professor · ligado' : 'Computador do Professor · desligado';
  }
  final partes = <String>[
    if (pairing.alunoDe(s.deviceId) != null) pairing.nomeDe(s),
    on ? 'Ligado' : 'Desligado',
    if (pairing.professorQueTravou(s.deviceId) case final p?) 'na aula de $p',
  ];
  return partes.join(' · ');
}

/// Confirma e fecha todas as abas do computador.
Future<void> confirmarFecharAbas(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final ok = await confirmar(
    context,
    titulo: 'Fechar todas as abas',
    mensagem: 'Fechar todas as abas de ${pairing.nomeDoPc(deviceId)}? '
        'Fica uma aba vazia.',
    acao: 'Fechar tudo',
  );
  if (!ok || !context.mounted) return;
  pairing.fecharTodasAsAbasEm(deviceId);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Fechando todas as abas…')));
}

/// Sair da conta, reiniciar ou desligar um computador, com confirmação.
Future<void> mostrarEnergiaNoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final acao = await showModalBottomSheet<AcaoEnergia>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(nome, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final a in AcaoEnergia.values)
            ListTile(
              leading: Icon(a.icone),
              title: Text(a.rotulo),
              subtitle: Text(a.efeito),
              onTap: () => Navigator.pop(ctx, a),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (acao == null || !context.mounted) return;
  await confirmarEnergiaNoPc(context, pairing, deviceId, nome, acao);
}

/// "Quem está neste computador?": escolhe um aluno livre da aula, cadastra
/// um novo, tira o aluno ou tira uma foto para descobrir.
Future<void> escolherAlunoDoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  void snack(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final disponiveis = pairing.alunosDisponiveis;
  final atual = pairing.alunoDe(deviceId);
  final pc = pairing.pcPorId(deviceId);
  final ligado = pc != null && pairing.isOnline(pc);
  final escolhido = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              atual == null ? 'Quem está neste computador?' : 'Trocar $atual por:',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          if (ligado)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Não sei quem é — tirar foto'),
              onTap: () => Navigator.pop(ctx, ' foto'),
            ),
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Cadastrar aluno novo'),
            onTap: () => Navigator.pop(ctx, ' novo'),
          ),
          if (atual != null)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('Tirar o aluno do computador'),
              onTap: () => Navigator.pop(ctx, ' remover'),
            ),
          if (disponiveis.isNotEmpty) const TituloDeSecao('Alunos sem computador'),
          if (disponiveis.isEmpty && atual == null)
            const ListTile(
              dense: true,
              title: Text('Nenhum aluno livre — cadastre um novo acima.'),
            ),
          for (final a in disponiveis)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(a),
              onTap: () => Navigator.pop(ctx, a),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (escolhido == null || !context.mounted) return;
  if (escolhido == ' foto') {
    await mostrarImagemDoPc(context, pairing, deviceId, pairing.nomeDoPc(deviceId), tela: false);
    if (context.mounted) await escolherAlunoDoPc(context, pairing, deviceId);
    return;
  }
  if (escolhido == ' remover') {
    await pairing.desvincularAluno(deviceId);
    return;
  }
  if (escolhido == ' novo') {
    final nome = await pedirTexto(
      context,
      titulo: 'Aluno novo',
      rotulo: 'Nome do aluno',
      dica: 'ex.: William',
      acao: 'Cadastrar',
      capitalizacao: TextCapitalization.words,
    );
    if (nome == null) return;
    final erro = await pairing.cadastrarEVincularAluno(deviceId, nome);
    if (context.mounted) snack(erro ?? '$nome está neste computador.');
    return;
  }
  // Escola: o computador pode estar preso na aula de outro professor.
  final erro = await pairing.vincularAluno(deviceId, escolhido);
  if (erro != null && context.mounted) snack(erro);
}
