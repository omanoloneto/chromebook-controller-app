// Tela de um computador: as ações do dia a dia no alto, depois o que está na
// tela, as abas, os programas, os últimos sites e os registros. As raras
// (renomear, número, telão, atualizar, desconectar) ficam no ⋮. Foto da câmera
// e captura da tela são pedidos avulsos do professor — nunca contínuos.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import '../util/abrir_no_celular.dart';
import '../util/versao.dart';
import 'acoes_do_pc.dart';
import 'archive_page.dart';
import 'chat_page.dart';
import 'componentes.dart';
import 'faixa_entrega.dart';
import 'fotos_de_entrada_page.dart';
import 'media_page.dart';
import 'theme.dart';
import 'trava_sheet.dart';
import 'visualizador.dart';

/// Domínio de uma URL para exibição compacta ("pt.khanacademy.org").
String dominioDe(String url) {
  try {
    final host = Uri.parse(url).host;
    return host.isEmpty ? url : host;
  } catch (_) {
    return url;
  }
}

/// Sheet de liberação de sites bloqueados num computador (ações dele). Não
/// exige aula: vale até bloquear de novo ou até o próximo "Encerrar aula".
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
                title: const Text('Liberar sites neste computador'),
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
                        ? 'Liberadas até o aluno sair da conta'
                        : 'Bloqueadas — liberar vale até o aluno sair da conta',
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
                    liberados.contains(p) ? 'Liberado neste computador' : 'Bloqueado',
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
              ? 'Nenhum computador com aluno nesta aula ainda.'
              : 'Nenhum computador conectado ainda.',
        );
        return false;
      }
      // A faixa da aba Aula acompanha a entrega PC a PC.
      pairing.abrirEmTodos(u);
    } else {
      // A faixa da tela do PC diz se ele recebeu.
      pairing.abrirEm(deviceId, u);
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
                      : 'Abrir um site em ${nomePc ?? 'este computador'}',
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
                      tooltip: turma ? 'Abrir na turma toda' : 'Abrir neste computador',
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
                            pairing.fecharSiteEmTodos(dominioDe(f.url));
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

/// Confirma e desfaz o vínculo com o computador. Retorna true se desvinculou.
Future<bool> confirmarEsquecerPc(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nome,
) async {
  final ok = await confirmar(
    context,
    titulo: 'Desconectar $nome',
    mensagem: 'O computador volta a mostrar o código de conexão e some da sua '
        'lista. Para usar de novo, é só ler o QR Code outra vez.',
    acao: 'Desconectar',
    destrutiva: true,
  );
  if (!ok) return false;
  await pairing.esquecerPc(deviceId);
  return true;
}

/// Renomeia o computador (o nome que aparece quando não há aluno nele).
Future<void> mostrarDialogoRenomear(
  BuildContext context,
  PairingController pairing,
  String deviceId,
  String nomeAtual,
) async {
  final novo = await pedirTexto(
    context,
    titulo: 'Nome do computador',
    dica: 'Ex.: Unidade 7 (fundo da sala)',
    inicial: nomeAtual,
  );
  if (novo != null) await pairing.renomear(deviceId, novo);
}

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
                ? 'Não veio a tela. Esse computador precisa ter o Celita OS, com o aluno já dentro da conta dele.'
                : 'Não veio a foto. O computador pode estar desligado, ou a câmera bloqueada pelo administrador.',
          ),
        ),
      );
    return;
  }
  final agora = DateTime.now();
  final hora = '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
  await abrirImagem(
    context,
    bytes: bytes,
    titulo: tela ? 'Tela — $nome' : 'Quem está no computador — $nome',
    legenda: tela ? 'Tela às $hora' : 'Foto da câmera às $hora',
    nomeArquivo: nomeParaGaleria('${tela ? 'Tela' : 'Foto'} $nome', agora.millisecondsSinceEpoch),
    onExcluir: () => pairing.apagarCaptura(deviceId),
    avisoAoExcluir: 'A captura sai da nuvem. No computador ela não fica guardada. Não '
        'dá para desfazer.',
  );
}

/// Altera o número da unidade (se for de outro computador, os dois trocam).
Future<void> mostrarDialogoNumeroUnidade(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) async {
  final atual = pairing.numeroDe(deviceId);
  final texto = await pedirTexto(
    context,
    titulo: 'Número da unidade',
    dica: 'Ex.: 7',
    ajuda: 'Se o número já for de outro computador, os dois trocam.',
    inicial: atual?.toString() ?? '',
    numero: true,
  );
  if (texto == null || !context.mounted) return;
  final numero = int.tryParse(texto);
  final erro = numero == null
      ? 'Digite um número de 1 a 9999.'
      : await pairing.alterarNumeroUnidade(deviceId, numero);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(erro ?? 'Agora é a Unidade $numero.')));
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
  PairingController get _pairing => widget.pairing;
  String get _id => widget.deviceId;

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

  static String _hora(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _atualizadoHa(DateTime? t) {
    if (t == null) return 'ainda sem dados';
    final s = DateTime.now().difference(t).inSeconds;
    return s < 60 ? 'há $s s' : 'há ${s ~/ 60} min';
  }

  Future<void> _fecharPorDominio(String url) async {
    final dominio = dominioDe(url);
    final ok = await confirmar(
      context,
      titulo: 'Fechar $dominio',
      mensagem: 'Fechar todas as abas de $dominio neste computador?',
      acao: 'Fechar',
    );
    if (!ok || !mounted) return;
    _pairing.fecharSiteEm(_id, dominio);
    _snack('Fechando $dominio…');
  }

  void _fecharAba(String url) {
    _pairing.fecharAbaEm(_id, url);
    _snack('Fechando a aba…');
  }

  void _abrirNoTelao(String url) {
    _pairing.abrirNoPcProfessor(url);
    _snack('Abrindo no Computador do Professor…');
  }

  Future<void> _atualizar(String nome) async {
    final erro = await _pairing.atualizarPc(_id);
    if (!mounted) return;
    _snack(
      erro ??
          '$nome vai baixar e instalar a atualização sozinho. A versão nova '
              'aparece aqui quando terminar.',
    );
  }

  void _alternarPcProfessor(String nome) {
    final ehProfessor = _pairing.ehPcProfessor(_id);
    _pairing.marcarPcProfessor(ehProfessor ? null : _id);
    _snack(
      ehProfessor
          ? '$nome voltou a ser computador de aluno.'
          : '$nome agora é o Computador do Professor.',
    );
  }

  Future<void> _desconectar(String nome) async {
    final saiu = await confirmarEsquecerPc(context, _pairing, _id, nome);
    if (saiu && mounted) Navigator.of(context).pop();
  }

  void _abrirPagina(Widget pagina) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));

  @override
  Widget build(BuildContext context) {
    final s = _pairing.pcPorId(_id);
    if (s == null && _pairing.carregandoPc(_id)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EstadoVazio(
          icone: Icons.link_off,
          titulo: 'Computador desconectado',
          texto: 'Este computador não está mais conectado ao app.',
        ),
      );
    }
    final t = Theme.of(context);
    final nome = _pairing.nomeDe(s);
    final on = _pairing.isOnline(s);
    final telao = _pairing.ehPcProfessor(_id);
    final meuRecado = !telao && _pairing.professorQueTravou(_id) == null;
    final naoLidas = meuRecado ? _pairing.naoLidasDe(_id) : 0;
    void conversar() => abrirConversa(context, _pairing, _id);
    final sinais = <Widget>[
      if (!telao) ...chipsDeTrava(context, _pairing, _id),
      if (meuRecado && _pairing.maoLevantada(_id))
        Selo('Mão levantada', icone: Icons.back_hand, tom: Tom.atencao, onTap: conversar),
      if (naoLidas > 0)
        Selo(
          naoLidas == 1 ? '1 mensagem nova' : '$naoLidas mensagens novas',
          icone: Icons.chat_bubble,
          tom: Tom.primario,
          onTap: conversar,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_pairing.nomeDoPc(_id), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              situacaoDoPc(_pairing, s),
              style: t.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [_menuMais(s, nome), const SizedBox(width: 4)],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          // Confirmação do último envio para este computador ("Ana recebeu").
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FaixaEntrega(pairing: _pairing, deviceId: _id, cartao: true),
          ),
          if (on && !telao && s.alerta != null) _alerta(s.alerta!),
          if (sinais.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: sinais),
            ),
          Cartao(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AcoesDoPc(
              contexto: context,
              pairing: _pairing,
              deviceId: _id,
              onIrParaSites: widget.onIrParaSites,
            ),
          ),
          ..._secaoAbas(s),
          if (s.apps.isNotEmpty) ..._secaoProgramas(s),
          if (telao) _avisoTelao() else ..._secaoUltimosSites(s),
          _secaoRegistros(s),
          _secaoSobre(s),
        ],
      ),
    );
  }

  Widget _menuMais(PcSession s, String nome) {
    final on = _pairing.isOnline(s);
    final celita = temCelita(s.versaoExt);
    final telao = _pairing.ehPcProfessor(_id);
    final desatualizado = _pairing.desatualizado(s);
    PopupMenuItem<String> item(
      String valor,
      IconData icone,
      String titulo, {
      String? subtitulo,
      bool habilitado = true,
      bool perigo = false,
    }) {
      final cor = perigo ? Theme.of(context).colorScheme.error : null;
      return PopupMenuItem(
        value: valor,
        enabled: habilitado,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icone, color: cor),
          title: Text(titulo, style: TextStyle(color: cor)),
          subtitle: subtitulo == null ? null : Text(subtitulo),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Mais opções',
      onSelected: (v) {
        switch (v) {
          case 'renomear':
            mostrarDialogoRenomear(context, _pairing, _id, nome);
          case 'numero':
            mostrarDialogoNumeroUnidade(context, _pairing, _id);
          case 'professor':
            _alternarPcProfessor(nome);
          case 'atualizar':
            _atualizar(nome);
          case 'desconectar':
            _desconectar(nome);
        }
      },
      itemBuilder: (_) => [
        item('renomear', Icons.edit_outlined, 'Renomear'),
        item('numero', Icons.pin_outlined, 'Alterar número da unidade'),
        item(
          'professor',
          telao ? Icons.co_present : Icons.co_present_outlined,
          telao ? 'Deixar de ser o Computador do Professor' : 'Usar como Computador do Professor',
          subtitulo: telao ? null : 'Sem bloqueios nem monitoramento; recebe os avisos',
        ),
        item(
          'atualizar',
          Icons.system_update_alt,
          'Atualizar o Celita OS agora',
          habilitado: on && celita,
          subtitulo: !celita
              ? 'Só nos computadores com Celita OS'
              : desatualizado
                  ? 'Este computador está desatualizado'
                  : 'Baixa e instala o que houver de novo',
        ),
        const PopupMenuDivider(),
        item('desconectar', Icons.link_off, 'Desconectar este computador', perigo: true),
      ],
    );
  }

  Widget _alerta(String site) {
    final c = cores(context);
    return Cartao(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      cor: c.alertaBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.alertaFg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Alerta: aba de $site aberta',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.alertaFg),
            ),
          ),
        ],
      ),
    );
  }

  /// Menu de um link: abrir no celular ou no telão; nas abas, também fechar.
  Widget _menuDoLink(String url, {bool aba = false}) {
    final telao = _pairing.pcProfessorOnline;
    return PopupMenuButton<String>(
      tooltip: aba ? 'Opções da aba' : 'Opções do link',
      onSelected: (v) {
        switch (v) {
          case 'celular':
            abrirNoCelular(context, url);
          case 'telao':
            _abrirNoTelao(url);
          case 'aba':
            _fecharAba(url);
          case 'dominio':
            _fecharPorDominio(url);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'celular',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.smartphone),
            title: Text('Abrir no meu celular'),
          ),
        ),
        PopupMenuItem(
          value: 'telao',
          enabled: telao,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.co_present_outlined),
            title: const Text('Abrir no Computador do Professor'),
            subtitle: telao
                ? null
                : Text(
                    _pairing.pcProfessorId == null
                        ? 'Nenhum Computador do Professor definido'
                        : 'O Computador do Professor está desligado',
                  ),
          ),
        ),
        if (aba) ...[
          const PopupMenuItem(
            value: 'aba',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.close),
              title: Text('Fechar esta aba'),
            ),
          ),
          PopupMenuItem(
            value: 'dominio',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tab_unselected),
              title: Text('Fechar todas de ${dominioDe(url)}'),
            ),
          ),
        ],
      ],
    );
  }

  /// Linha de um site: ícone (ou hora), título, domínio e o menu.
  Widget _linhaDoSite({
    required Widget inicio,
    required String titulo,
    required String url,
    bool aba = false,
  }) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          SizedBox(width: 40, child: Center(child: inicio)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
                Text(dominioDe(url), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
              ],
            ),
          ),
          _menuDoLink(url, aba: aba),
        ],
      ),
    );
  }

  Widget _cartaoDeLinhas(List<Widget> linhas, {double recuo = 68}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < linhas.length; i++) ...[
            if (i > 0) Divider(indent: recuo),
            linhas[i],
          ],
        ],
      ),
    );
  }

  Widget _vazio(String texto) => Cartao(
        child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
      );

  List<Widget> _secaoAbas(PcSession s) {
    final t = Theme.of(context);
    final ativa = s.abaAtiva;
    final outras = [for (final a in s.tabs) if (!identical(a, ativa)) a];
    return [
      TituloDeSecao(
        'Na tela agora',
        acao: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(_atualizadoHa(s.lastReportAt), style: t.textTheme.bodySmall),
        ),
      ),
      if (ativa == null)
        _vazio('Nenhuma aba aberta informada.')
      else
        Cartao(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ativa.title.isEmpty ? '(sem título)' : ativa.title,
                      style: t.textTheme.titleSmall?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(ativa.url, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              _menuDoLink(ativa.url, aba: true),
            ],
          ),
        ),
      if (outras.isNotEmpty) ...[
        TituloDeSecao('Outras abas · ${outras.length}'),
        _cartaoDeLinhas([
          for (final a in outras)
            GestureDetector(
              // Toque longo = atalho para fechar o site; o ⋮ é o visível.
              onLongPress: () => _fecharPorDominio(a.url),
              child: _linhaDoSite(
                inicio: Icon(Icons.tab_outlined, color: t.colorScheme.onSurfaceVariant),
                titulo: a.title.isEmpty ? '(sem título)' : a.title,
                url: a.url,
                aba: true,
              ),
            ),
        ]),
      ],
    ];
  }

  List<Widget> _secaoProgramas(PcSession s) {
    final t = Theme.of(context);
    return [
      TituloDeSecao('Programas abertos · ${s.apps.length}'),
      _cartaoDeLinhas(
        [
          for (final a in s.apps)
            ListTile(
              leading: Icon(Icons.desktop_windows_outlined, color: t.colorScheme.onSurfaceVariant),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: a.title.isEmpty
                  ? null
                  : Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        recuo: 56,
      ),
    ];
  }

  /// Sites visitados (em memória, desde que o app abriu); o histórico de 15
  /// dias fica em Registros.
  List<Widget> _secaoUltimosSites(PcSession s) {
    final t = Theme.of(context);
    final historico = s.history.reversed.take(20).toList();
    return [
      TituloDeSecao(
        'Últimos sites',
        acao: TextButton(
          onPressed: () => _abrirPagina(ArchivePage(pairing: _pairing, deviceId: _id)),
          child: const Text('Histórico completo'),
        ),
      ),
      if (historico.isEmpty)
        _vazio('Nenhuma visita desde que o app abriu.')
      else
        _cartaoDeLinhas([
          for (final e in historico)
            _linhaDoSite(
              inicio: Text(_hora(e.ts), style: t.textTheme.labelMedium),
              titulo: e.title.isEmpty ? e.url : e.title,
              url: e.url,
            ),
        ]),
    ];
  }

  Widget _avisoTelao() {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Cartao(
        child: Row(
          children: [
            Icon(Icons.co_present_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Computador do Professor: sem monitoramento de histórico, '
                'alertas ou bloqueios.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoRegistros(PcSession s) {
    final so = temCelita(s.versaoExt) ? null : 'Só nos computadores com Celita OS';
    ListTile linha(IconData icone, String titulo, String? subtitulo, Widget pagina) => ListTile(
          leading: Icon(icone),
          title: Text(titulo),
          subtitle: subtitulo == null ? null : Text(subtitulo),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _abrirPagina(pagina),
        );
    return GrupoDeOpcoes(
      titulo: 'Registros',
      children: [
        linha(
          Icons.history,
          'Histórico de navegação',
          so ?? 'Últimos 15 dias',
          ArchivePage(pairing: _pairing, deviceId: _id),
        ),
        linha(
          Icons.photo_camera_front_outlined,
          'Fotos de início de sessão',
          so,
          FotosDeEntradaPage(pairing: _pairing, deviceId: _id),
        ),
        linha(
          Icons.photo_library_outlined,
          'Fotos e vídeos da Câmera',
          so,
          MediaPage(pairing: _pairing, deviceId: _id),
        ),
      ],
    );
  }

  Widget _secaoSobre(PcSession s) {
    final t = Theme.of(context);
    final on = _pairing.isOnline(s);
    final celita = temCelita(s.versaoExt);
    final desatualizado = _pairing.desatualizado(s);
    final numero = _pairing.numeroDe(_id);
    final curta = versaoCurta(s.versaoExt);
    final versao = celita
        ? (s.versaoOs == null ? 'Celita OS' : 'Celita OS ${s.versaoOs}')
        : (curta == null ? 'Desconhecida' : 'Extensão $curta');
    ListTile linha(IconData icone, String titulo, String valor, {Widget? fim, Color? cor}) =>
        ListTile(
          leading: Icon(icone),
          title: Text(titulo),
          subtitle: Text(valor, style: cor == null ? null : TextStyle(color: cor)),
          trailing: fim,
        );
    return GrupoDeOpcoes(
      titulo: 'Sobre este computador',
      children: [
        linha(Icons.badge_outlined, 'Nome', _pairing.nomeDe(s)),
        linha(Icons.pin_outlined, 'Unidade', numero == null ? 'Sem número' : '$numero'),
        if (s.usuario != null) linha(Icons.account_circle_outlined, 'Conta aberta', s.usuario!),
        linha(
          Icons.memory_outlined,
          'Versão',
          desatualizado ? '$versao · a mais nova é ${_pairing.versaoPublicada}' : versao,
          cor: desatualizado ? t.colorScheme.error : null,
          fim: desatualizado && on && celita
              ? TextButton(
                  onPressed: () => _atualizar(_pairing.nomeDe(s)),
                  child: const Text('Atualizar'),
                )
              : null,
        ),
      ],
    );
  }
}
