// Tela de detalhe de um PC: aba ativa, abas abertas, programas abertos e
// histórico de navegação (dados ficam em memória). Foto da câmera e captura
// da tela são pedidos avulsos do professor — nunca contínuos.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import '../util/abrir_no_celular.dart';
import '../util/versao.dart';
import 'archive_page.dart';
import 'theme.dart';

/// Domínio de uma URL para exibição compacta ("pt.khanacademy.org").
String dominioDe(String url) {
  try {
    final host = Uri.parse(url).host;
    return host.isEmpty ? url : host;
  } catch (_) {
    return url;
  }
}

/// Sheet de liberação de sites bloqueados p/ UM PC (usado aqui e no menu ⋮
/// da aba Aula). Não exige aula: vale até bloquear de novo ou até o próximo
/// "Encerrar aula".
Future<void> mostrarSheetLiberarSites(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final professor = pairing.professorQueTravou(deviceId);
  if (professor != null) {
    snack('Está na aula de $professor.');
    return;
  }
  final padroes = pairing.padroesBloqueio;
  if (padroes.isEmpty && !pairing.filtros.ias) {
    snack('Nenhum site bloqueado nas regras.');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final liberados = pairing.liberacoesDe(deviceId);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Desbloquear sites para este PC'),
                subtitle: Text(
                  pairing.aulaAtiva
                      ? 'Vale até você bloquear de novo ou encerrar a aula.'
                      : 'Vale até você bloquear de novo ou encerrar a sua '
                          'próxima aula.',
                ),
              ),
              const Divider(height: 1),
              if (pairing.filtros.ias)
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('IAs (Gemini, ChatGPT e outras)'),
                  subtitle: Text(
                    pairing.iasLiberadasEm(deviceId)
                        ? 'LIBERADAS até o aluno sair da conta'
                        : 'bloqueadas — liberar vale até o aluno sair da conta',
                  ),
                  value: pairing.iasLiberadasEm(deviceId),
                  onChanged: (ligar) async {
                    final erro = await pairing.liberarIas(deviceId, ligar);
                    if (erro != null) snack(erro);
                    setSheet(() {});
                  },
                ),
              for (final p in padroes)
                SwitchListTile(
                  title: Text(p),
                  subtitle: Text(
                    liberados.contains(p) ? 'LIBERADO neste PC' : 'bloqueado',
                  ),
                  value: liberados.contains(p),
                  onChanged: (ligar) async {
                    if (ligar) {
                      final erro = await pairing.liberarPara(deviceId, p);
                      if (erro != null) snack(erro);
                    } else {
                      await pairing.revogarLiberacao(deviceId, p);
                    }
                    setSheet(() {});
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Sheet "Abrir um site": alvo = a turma (sem [deviceId]) ou um PC. Os
/// favoritos preenchem o campo; "Abrir" manda direto.
Future<void> mostrarSheetAbrirSite(
  BuildContext context,
  PairingController pairing, {
  String? deviceId,
  String? nomePc,
  VoidCallback? onEditarFavoritos,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final turma = deviceId == null;
  final ctrl = TextEditingController(text: 'https://');

  // true = enviou (a sheet fecha).
  bool abrir(String url) {
    final u = url.trim();
    if (u.isEmpty || u == 'https://' || u == 'http://') {
      snack('Digite ou escolha um site primeiro.');
      return false;
    }
    if (turma) {
      final n = pairing.pcsAlvoCount;
      if (n == 0) {
        snack(
          pairing.aulaAtiva
              ? 'Nenhum PC com aluno nesta aula ainda.'
              : 'Nenhum PC conectado ainda.',
        );
        return false;
      }
      pairing.abrirEmTodos(u);
      snack('Enviado para $n PC(s).');
    } else {
      pairing.abrirEm(deviceId, u);
      snack('Enviado para ${nomePc ?? 'este PC'}.');
    }
    return true;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final favoritos = pairing.favoritos;
      final estiloBotao = TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      );
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  turma
                      ? 'Abrir um site na turma'
                      : 'Abrir um site em ${nomePc ?? 'este PC'}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Endereço do site',
                    hintText: 'https://...',
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.send,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      tooltip: turma ? 'Abrir na turma toda' : 'Abrir neste PC',
                      onPressed: () {
                        if (abrir(ctrl.text)) Navigator.pop(ctx);
                      },
                    ),
                  ),
                  onSubmitted: (v) {
                    if (abrir(v)) Navigator.pop(ctx);
                  },
                ),
              ),
              for (final f in favoritos)
                ListTile(
                  leading: Icon(Icons.star, color: cores(ctx).favorito),
                  title: Text(
                    f.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    dominioDe(f.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => ctrl.text = f.url,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        style: estiloBotao,
                        onPressed: () {
                          if (abrir(f.url)) Navigator.pop(ctx);
                        },
                        child: const Text('Abrir'),
                      ),
                      if (turma)
                        TextButton(
                          style: estiloBotao,
                          onPressed: () {
                            final dominio = dominioDe(f.url);
                            pairing.fecharSiteEmTodos(dominio);
                            snack('Fechando $dominio na turma.');
                            Navigator.pop(ctx);
                          },
                          child: const Text('Fechar na turma'),
                        ),
                    ],
                  ),
                ),
              if (onEditarFavoritos != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar favoritos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEditarFavoritos();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Confirmação de "Esquecer este PC" (usada aqui e no menu ⋮ da aba Aula).
/// Retorna true se desvinculou.
Future<bool> confirmarEsquecerPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Desconectar este PC'),
      content: Text(
        'Desfazer o vínculo com "$nome"?\n\n'
        'O Chromebook volta a mostrar o código de conexão e some da sua lista.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Desconectar'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await pairing.esquecerPc(deviceId);
    return true;
  }
  return false;
}

/// Diálogo de renomear (usado aqui e na home via long-press).
Future<void> mostrarDialogoRenomear(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nomeAtual,
) async {
  final ctrl = TextEditingController(text: nomeAtual);
  final novo = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nome do aluno'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Ex.: Maria (fundo da sala)',
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
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  if (novo != null) await pairing.renomear(deviceId, novo);
}

/// Diálogo "Enviar mensagem" (popup no Chrome do aluno) — aqui e na aba Aula.
/// Pede uma imagem ao PC e mostra num dialog: [tela] false = foto da câmera
/// (quem está sentado ali; o LED do aluno acende), true = captura da tela,
/// que só o agente do Celita OS atende.
Future<void> mostrarImagemDoPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome, {
  required bool tela,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final bytes = await esperarComSpinner(
    context,
    tela ? 'Buscando a tela…' : 'Tirando a foto…',
    tela ? pairing.tirarFotoTela(deviceId) : pairing.tirarFotoCamera(deviceId),
  );
  if (!context.mounted || !continuaNaFrente(context)) return;
  if (bytes == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tela
                ? 'Não veio a tela. Esse PC precisa ter o Celita OS, com o aluno já dentro da conta dele.'
                : 'Não veio a foto. O PC pode estar desligado, ou a câmera bloqueada pelo administrador.',
          ),
        ),
      );
    return;
  }
  await mostrarDialogoImagem(
    context,
    bytes: bytes,
    titulo: tela ? 'Tela — $nome' : 'Quem está no PC — $nome',
  );
}

/// Spinner enquanto [tarefa] roda. Fecha só a própria rota: o voltar do
/// Android ou o toque numa notificação podem tê-lo tirado antes, e um pop às
/// cegas fecharia a tela de baixo.
Future<T> esperarComSpinner<T>(
  BuildContext context,
  String texto,
  Future<T> tarefa,
) async {
  final navigator = Navigator.of(context);
  final rota = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(texto)),
        ],
      ),
    ),
  );
  unawaited(navigator.push(rota));
  try {
    return await tarefa;
  } finally {
    if (rota.isActive) navigator.removeRoute(rota);
  }
}

/// A tela de [context] continua no topo (nada abriu por cima). Checar
/// `mounted` antes.
bool continuaNaFrente(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent ?? true;

/// Diálogo com uma imagem do PC (foto da câmera ou tela) e legenda opcional.
Future<void> mostrarDialogoImagem(
  BuildContext context, {
  required Uint8List bytes,
  required String titulo,
  String? legenda,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                titulo,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Image.memory(bytes),
            if (legenda != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  legenda,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> mostrarDialogoMensagem(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final ctrl = TextEditingController();
  final texto = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Mensagem para $nome'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 500,
        maxLines: 4,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Ex.: Volte para a atividade, por favor.',
          helperText: 'Abre na tela do PC na hora, só para este aluno.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Enviar'),
        ),
      ],
    ),
  );
  if (texto == null || !context.mounted) return;
  final erro = await pairing.enviarMensagem(deviceId, texto);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(erro ?? 'Mensagem enviada a $nome.')),
  );
}

/// Diálogo de alterar o número da unidade (aqui e no menu da aba Aula).
Future<void> mostrarDialogoNumeroUnidade(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final atual = pairing.numeroDe(deviceId);
  final ctrl = TextEditingController(text: atual?.toString() ?? '');
  final texto = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Número da unidade'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: 'Ex.: 7',
          helperText: 'Se o número já for de outro PC, os dois trocam.',
          helperMaxLines: 2,
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
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  if (texto == null || !context.mounted) return;
  final numero = int.tryParse(texto.trim());
  final erro = numero == null
      ? 'Digite um número de 1 a 9999.'
      : await pairing.alterarNumeroUnidade(deviceId, numero);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(erro ?? 'Agora é a Unidade $numero.')),
  );
}

/// Nome de rota da tela de um PC: o toque numa notificação volta a ela em
/// vez de empilhar outra igual.
String rotaDoPc(String deviceId) => '/pc/$deviceId';

Route<void> rotaDevicePage(
  PairingController pairing,
  String deviceId, {
  VoidCallback? onIrParaSites,
}) =>
    MaterialPageRoute(
      settings: RouteSettings(name: rotaDoPc(deviceId)),
      builder: (_) => DevicePage(
        pairing: pairing,
        deviceId: deviceId,
        onIrParaSites: onIrParaSites,
      ),
    );

class DevicePage extends StatefulWidget {
  const DevicePage({
    super.key,
    required this.pairing,
    required this.deviceId,
    this.onIrParaSites,
  });

  final PairingController pairing;
  final String deviceId;

  /// Leva à aba Sites (o "Editar favoritos" da sheet de abrir site). Null
  /// quando a tela veio de fora do shell (toque em notificação).
  final VoidCallback? onIrParaSites;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
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

  String _hora(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _fecharPorDominio(String url) async {
    final dominio = dominioDe(url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar site neste PC'),
        content: Text('Fechar todas as abas de $dominio neste PC?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.pairing.fecharSiteEm(widget.deviceId, dominio);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Fechando $dominio…')));
    }
  }

  String _atualizadoHa(DateTime? t) {
    if (t == null) return 'sem dados de abas ainda';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'Atualizado há ${s}s';
    return 'Atualizado há ${s ~/ 60}min';
  }

  Future<void> _liberarSites() =>
      mostrarSheetLiberarSites(context, widget.pairing, widget.deviceId);

  void _abrirSite(String nome) => mostrarSheetAbrirSite(
        context,
        widget.pairing,
        deviceId: widget.deviceId,
        nomePc: nome,
        onEditarFavoritos: widget.onIrParaSites,
      );

  Future<void> _atualizar(String nome) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await widget.pairing.atualizarPc(widget.deviceId);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            erro ??
                '$nome vai baixar e instalar a atualização sozinho. A versão '
                    'nova aparece aqui quando terminar.',
          ),
        ),
      );
  }

  void _alternarPcProfessor(String nome) {
    final ehProfessor = widget.pairing.ehPcProfessor(widget.deviceId);
    widget.pairing.marcarPcProfessor(ehProfessor ? null : widget.deviceId);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ehProfessor
                ? '$nome voltou a ser PC de aluno.'
                : '$nome agora é o Computador do Professor.',
          ),
        ),
      );
  }

  void _abrirNoTelao(String url) {
    widget.pairing.abrirNoPcProfessor(url);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Abrindo no Computador do Professor…')),
      );
  }

  void _abrirNoCelular(String url) => abrirNoCelular(context, url);

  void _verHistorico() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArchivePage(
            pairing: widget.pairing,
            deviceId: widget.deviceId,
          ),
        ),
      );

  /// Item de menu "Abrir no meu celular" — abre a URL no navegador do próprio
  /// celular do professor (sempre disponível; não depende de PC marcado).
  PopupMenuItem<String> _itemMenuCelular() {
    return const PopupMenuItem(
      value: 'celular',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.smartphone),
        title: Text('Abrir no meu celular'),
      ),
    );
  }

  /// Item de menu "Abrir no Computador do Professor" (usado na aba ativa, nas
  /// abas abertas e no histórico). Desabilitado explica o porquê.
  PopupMenuItem<String> _itemMenuTelao() {
    return PopupMenuItem(
      value: 'telao',
      enabled: widget.pairing.pcProfessorOnline,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.co_present),
        title: const Text('Abrir no Computador do Professor'),
        subtitle: widget.pairing.pcProfessorOnline
            ? null
            : Text(
                widget.pairing.pcProfessorId == null
                    ? 'nenhum Computador do Professor definido'
                    : 'O Computador do Professor está offline',
              ),
      ),
    );
  }

  Future<void> _confirmarFecharTudo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar todas as abas'),
        content: const Text(
          'Fechar TODAS as abas deste PC? Ele fica com uma aba vazia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fechar tudo'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.pairing.fecharTodasAsAbasEm(widget.deviceId);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fechando todas as abas…')));
    }
  }

  Future<void> _confirmarEsquecer(String nome) async {
    final saiu = await confirmarEsquecerPc(
      context,
      widget.pairing,
      widget.deviceId,
      nome,
    );
    if (saiu && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.pairing.pcPorId(widget.deviceId);
    if (s == null && widget.pairing.carregandoPc(widget.deviceId)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PC desconectado')),
        body: const Center(child: Text('Este PC não está mais conectado.')),
      );
    }
    final nome = widget.pairing.nomeDe(s);
    final on = widget.pairing.isOnline(s);
    final ativa = s.abaAtiva;
    final ehProfessor = widget.pairing.ehPcProfessor(widget.deviceId);
    final celita = temCelita(s.versaoExt);
    final desatualizado = widget.pairing.desatualizado(s);
    final maisNova = widget.pairing.versaoPublicada;
    final versao = !celita
        ? versaoCurta(s.versaoExt)
        : s.versaoOs == null
            ? null
            : 'Celita OS ${s.versaoOs}';

    return Scaffold(
      appBar: AppBar(
        title: Text(nome),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Renomear',
            onPressed: () => mostrarDialogoRenomear(
              context,
              widget.pairing,
              widget.deviceId,
              nome,
            ),
          ),
          // Ação destrutiva fora da barra: evita toque acidental.
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (v) {
              if (v == 'site') _abrirSite(nome);
              if (v == 'mensagem') {
                mostrarDialogoMensagem(
                  context,
                  widget.pairing,
                  widget.deviceId,
                  nome,
                );
              }
              if (v == 'numero') {
                mostrarDialogoNumeroUnidade(
                  context,
                  widget.pairing,
                  widget.deviceId,
                );
              }
              if (v == 'foto') {
                mostrarImagemDoPc(
                  context,
                  widget.pairing,
                  widget.deviceId,
                  nome,
                  tela: false,
                );
              }
              if (v == 'tela') {
                mostrarImagemDoPc(
                  context,
                  widget.pairing,
                  widget.deviceId,
                  nome,
                  tela: true,
                );
              }
              if (v == 'historico') _verHistorico();
              if (v == 'atualizar') _atualizar(nome);
              if (v == 'professor') _alternarPcProfessor(nome);
              if (v == 'esquecer') _confirmarEsquecer(nome);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'site',
                enabled: on,
                child: const ListTile(
                  leading: Icon(Icons.open_in_browser),
                  title: Text('Abrir um site neste PC'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'mensagem',
                enabled: on,
                child: const ListTile(
                  leading: Icon(Icons.chat_bubble_outline),
                  title: Text('Enviar mensagem'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'foto',
                enabled: on,
                child: const ListTile(
                  leading: Icon(Icons.photo_camera_outlined),
                  title: Text('Ver quem está no PC'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'tela',
                enabled: on,
                child: const ListTile(
                  leading: Icon(Icons.screenshot_monitor_outlined),
                  title: Text('Ver a tela do PC'),
                  subtitle: Text('só nos PCs com Celita OS'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'historico',
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Ver histórico'),
                  subtitle: temCelita(s.versaoExt)
                      ? null
                      : const Text('só nos PCs com Celita OS'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'atualizar',
                enabled: on && celita,
                child: ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('Atualizar o Celita OS agora'),
                  subtitle: Text(
                    !celita
                        ? 'só nos PCs com Celita OS'
                        : desatualizado
                            ? 'este PC está desatualizado'
                            : 'baixa e instala o que houver de novo',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'professor',
                child: ListTile(
                  leading: Icon(
                    ehProfessor ? Icons.co_present : Icons.co_present_outlined,
                  ),
                  title: Text(
                    ehProfessor
                        ? 'Deixar de ser o Computador do Professor'
                        : 'Usar como Computador do Professor',
                  ),
                  subtitle: ehProfessor
                      ? null
                      : const Text(
                          'sem bloqueios/monitoramento; recebe os avisos',
                        ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'numero',
                child: ListTile(
                  leading: Icon(Icons.pin),
                  title: Text('Alterar número da unidade'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'esquecer',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Desconectar este PC'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (on && s.alerta != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cores(context).alertaBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: cores(context).alertaFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alerta: aba de ${s.alerta} aberta',
                      style: TextStyle(color: cores(context).alertaFg),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: on ? cores(context).online : cores(context).offline,
              ),
              const SizedBox(width: 8),
              Text(on ? 'online' : 'offline'),
              const Spacer(),
              Text(
                _atualizadoHa(s.lastReportAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          if (versao != null || desatualizado)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (versao != null) celita ? versao : 'Versão $versao',
                  if (desatualizado) 'desatualizado (a mais nova é $maisNova)',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: desatualizado
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (widget.pairing.aulaAtiva) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.pairing.alunoDe(widget.deviceId) ??
                        'Nenhum aluno escolhido nesta aula',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _liberarSites,
                  icon: const Icon(Icons.lock_open),
                  label: Text(
                    widget.pairing.liberacoesDe(widget.deviceId).isEmpty
                        ? 'Desbloquear sites'
                        : 'Liberados: '
                            '${widget.pairing.liberacoesDe(widget.deviceId).length}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: on ? _confirmarFecharTudo : null,
                  icon: const Icon(Icons.tab_unselected),
                  label: const Text('Fechar abas'),
                ),
              ),
            ],
          ),
          if (s.usuario != null) ...[
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_circle_outlined),
              title: Text('Conta aberta no PC: ${s.usuario}'),
            ),
          ],
          const SizedBox(height: 16),
          Text('Aba ativa', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ativa == null
                  ? const Text('Sem aba ativa informada.')
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ativa.title.isEmpty
                                    ? '(sem título)'
                                    : ativa.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                ativa.url,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Opções da aba ativa',
                          onSelected: (v) {
                            if (v == 'celular') _abrirNoCelular(ativa.url);
                            if (v == 'telao') _abrirNoTelao(ativa.url);
                          },
                          itemBuilder: (_) => [_itemMenuCelular(), _itemMenuTelao()],
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Abas abertas (${s.tabs.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          if (s.tabs.isEmpty)
            const ListTile(dense: true, title: Text('Nenhuma aba informada.')),
          for (final t in s.tabs)
            ListTile(
              dense: true,
              leading: Icon(
                t.active ? Icons.tab : Icons.tab_unselected,
                color: t.active
                    ? cores(context).online
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(
                t.title.isEmpty ? '(sem título)' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(dominioDe(t.url)),
              // Long-press = atalho; o menu ⋮ é a affordance visível.
              onLongPress: () => _fecharPorDominio(t.url),
              trailing: PopupMenuButton<String>(
                tooltip: 'Opções da aba',
                onSelected: (v) {
                  if (v == 'aba') {
                    widget.pairing.fecharAbaEm(widget.deviceId, t.url);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Fechando a aba…')),
                      );
                  } else if (v == 'dominio') {
                    _fecharPorDominio(t.url);
                  } else if (v == 'telao') {
                    _abrirNoTelao(t.url);
                  } else if (v == 'celular') {
                    _abrirNoCelular(t.url);
                  }
                },
                itemBuilder: (_) => [
                  _itemMenuCelular(),
                  _itemMenuTelao(),
                  const PopupMenuItem(
                    value: 'aba',
                    child: Text('Fechar esta aba'),
                  ),
                  PopupMenuItem(
                    value: 'dominio',
                    child: Text('Fechar todas de ${dominioDe(t.url)}'),
                  ),
                ],
              ),
            ),
          if (s.apps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Programas abertos (${s.apps.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            for (final a in s.apps)
              ListTile(
                dense: true,
                leading: const Icon(Icons.desktop_windows_outlined),
                title: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: a.title.isEmpty ? null : Text(a.title),
              ),
          ],
          ..._secaoNavegacao(s, ehProfessor),
        ],
      ),
    );
  }

  /// Histórico guardado na nuvem: sempre habilitado, mesmo com o PC desligado.
  Widget _botaoHistorico(PcSession s) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _verHistorico,
            icon: const Icon(Icons.history),
            label: const Text('Ver histórico (15 dias)'),
          ),
          if (!temCelita(s.versaoExt))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'só nos PCs com Celita OS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  /// Sites visitados (em memória, desde que o app abriu). Telão: só o aviso
  /// (as fotos valem para ele também, então o botão do histórico fica).
  List<Widget> _secaoNavegacao(PcSession s, bool ehProfessor) {
    if (ehProfessor) {
      return [
        const SizedBox(height: 16),
        const ListTile(
          dense: true,
          leading: Icon(Icons.co_present),
          title: Text('Computador do Professor'),
          subtitle: Text(
            'Sem monitoramento de histórico, alertas ou bloqueios.',
          ),
        ),
        _botaoHistorico(s),
      ];
    }
    final historico = s.history.reversed.toList();
    return [
      const SizedBox(height: 16),
      Text(
        'Últimos sites',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      _botaoHistorico(s),
      const SizedBox(height: 4),
      if (historico.isEmpty)
        const ListTile(dense: true, title: Text('Nenhuma visita ainda.')),
      for (final e in historico)
        ListTile(
          dense: true,
          leading: Text(
            _hora(e.ts),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          title: Text(
            e.title.isEmpty ? e.url : e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(dominioDe(e.url)),
          trailing: PopupMenuButton<String>(
            tooltip: 'Opções do link',
            onSelected: (v) {
              if (v == 'celular') _abrirNoCelular(e.url);
              if (v == 'telao') _abrirNoTelao(e.url);
            },
            itemBuilder: (_) => [_itemMenuCelular(), _itemMenuTelao()],
          ),
        ),
    ];
  }
}
