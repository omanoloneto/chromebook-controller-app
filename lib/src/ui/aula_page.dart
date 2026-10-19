// Aba Aula: o painel da aula. Sem aula, começa uma pela turma; com aula, a
// turma no alto, as ações da turma a um toque, os recados quando houver e os
// computadores com o aluno, o site e os sinais de cada um.

import 'package:flutter/material.dart';

import '../cloud/entrega.dart';
import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import 'acoes_do_pc.dart';
import 'chamada_page.dart';
import 'chat_page.dart';
import 'componentes.dart';
import 'device_page.dart';
import 'energia_controles.dart';
import 'faixa_entrega.dart';
import 'fotos_de_entrada_page.dart';
import 'grade_telas.dart';
import 'home_sections.dart';
import 'prova_controles.dart';
import 'recados_page.dart';
import 'scan_page.dart';
import 'theme.dart';
import 'trava_sheet.dart';

class AulaPage extends StatefulWidget {
  const AulaPage({
    super.key,
    required this.pairing,
    required this.onIrParaSites,
    this.onIrParaSitesDaProva,
    this.onIrParaTurmas,
    this.visivel = true,
  });

  final PairingController pairing;

  /// Navega para a aba Sites (editar favoritos/regras).
  final VoidCallback onIrParaSites;

  /// Navega para a lista de sites permitidos na prova (aba Sites).
  final VoidCallback? onIrParaSitesDaProva;

  /// Navega para a aba Turmas (cadastrar a primeira turma).
  final VoidCallback? onIrParaTurmas;

  /// A aba Aula está na frente (a grade de telas só roda assim).
  final bool visivel;

  @override
  State<AulaPage> createState() => _AulaPageState();
}

class _AulaPageState extends State<AulaPage> {
  PairingController get _pairing => widget.pairing;

  /// Lista: desligados escondidos atrás de "Mostrar" quando há outros.
  bool _mostrarTodos = false;

  /// "Telas": a grade de miniaturas no lugar da lista.
  bool _grade = false;

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
    if (!mounted) return;
    // Aula encerrada (aqui ou noutra tela): a grade fecha junto.
    if (_grade && !_pairing.aulaAtiva) _grade = false;
    setState(() {});
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _abrirScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanPage(pairing: _pairing)),
    );
    if (mounted) setState(() {});
  }

  void _abrirSiteNaTurma() => mostrarSheetAbrirSite(
        context,
        _pairing,
        onEditarFavoritos: widget.onIrParaSites,
      );

  void _abrirFotosDeEntrada() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FotosDeEntradaPage(pairing: _pairing)),
      );

  void _abrirDevicePage(String deviceId) {
    Navigator.of(context).push(
      rotaDevicePage(
        _pairing,
        deviceId,
        onIrParaSites: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          widget.onIrParaSites();
        },
      ),
    );
  }

  void _acoesDoPc(String deviceId) => mostrarAcoesDoPc(
        context,
        _pairing,
        deviceId,
        onAbrirTela: () => _abrirDevicePage(deviceId),
        onIrParaSites: widget.onIrParaSites,
      );

  // ---- Sessão de aula --------------------------------------------------------------

  /// Começa a aula com a turma (do cartão) ou pergunta qual (sem turma).
  Future<void> _iniciarAula([String? turma]) async {
    final turmas = _pairing.turmas;
    if (turmas.isEmpty) {
      _snack('Cadastre uma turma primeiro, na aba Turmas.');
      return;
    }
    final escolhida = turma ??
        await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    'Iniciar aula com qual turma?',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                for (final t in turmas)
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(t.nome),
                    subtitle: Text(_alunos(t.alunos.length)),
                    onTap: () => Navigator.pop(ctx, t.nome),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
    if (escolhida == null) return;
    await _pairing.iniciarAula(escolhida);
    // A aula começa pela chamada: cada presença já diz a unidade.
    if (mounted) await Navigator.of(context).push(rotaChamada(_pairing));
  }

  Future<void> _encerrarAula() async {
    final n = _pairing.pcsAlvoCount; // só os com aluno
    final ok = await confirmar(
      context,
      titulo: 'Encerrar aula',
      mensagem: 'Fecha o navegador em ${_computadores(n)} com aluno, destrava '
          'as telas, desliga o modo prova e limpa os vínculos, as conversas e '
          'os recados desta aula.',
      acao: 'Encerrar aula',
      destrutiva: true,
    );
    if (ok) {
      setState(() => _grade = false);
      await _pairing.encerrarAula();
      // A faixa acompanha o fechamento do navegador PC a PC.
      _snack('Aula encerrada.');
    }
  }

  void _alternarGrade() {
    if (!_grade) {
      final sem = _pairing.motivoSemTurma;
      if (sem != null) {
        _snack(sem);
        return;
      }
    }
    setState(() => _grade = !_grade);
  }

  void _irParaSitesDaProva() => (widget.onIrParaSitesDaProva ?? widget.onIrParaSites)();

  // ---- Build -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final aula = _pairing.aulaAtiva && !_pairing.iniciando;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: aula ? 68 : null,
        title: aula ? _tituloDaAula() : const Text('Controle de Aula'),
        actions: [
          _botaoRecados(),
          _menuMais(),
          const SizedBox(width: 4),
        ],
      ),
      body: _pairing.iniciando
          ? const Center(child: CircularProgressIndicator())
          : _pairing.erroDeConexao != null
              ? _erroView()
              : _conteudo(_pairing.pcs),
    );
  }

  Widget _tituloDaAula() {
    final t = Theme.of(context).textTheme;
    final inicio = _pairing.inicioDaAula;
    final presentes = '${_pairing.totalVinculados} de '
        '${_pairing.totalAlunosDaTurma} presentes';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_pairing.turmaDaAula, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          inicio == null ? presentes : 'Desde ${_hora(inicio)} · $presentes',
          style: t.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // Recados: pedidos + mãos + conversas com não lidas.
  Widget _botaoRecados() {
    final n = _pairing.iniciando ? 0 : _pairing.recadosCount;
    return IconButton(
      tooltip: n == 0 ? 'Recados' : 'Recados ($n)',
      onPressed: () => abrirRecados(context, _pairing),
      icon: Badge.count(
        count: n,
        isLabelVisible: n > 0,
        child: const Icon(Icons.inbox_outlined),
      ),
    );
  }

  Widget _menuMais() {
    return PopupMenuButton<String>(
      tooltip: 'Mais opções',
      onSelected: (v) {
        if (v == 'conectar') _abrirScanner();
        if (v == 'fotos') _abrirFotosDeEntrada();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'conectar',
          child: ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Conectar computador'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_pairing.workspaceAtivo)
          const PopupMenuItem(
            value: 'fotos',
            child: ListTile(
              leading: Icon(Icons.photo_camera_front_outlined),
              title: Text('Fotos de início de sessão'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Widget _erroView() {
    final naoLiberado = _pairing.naoLiberadoNaEscola;
    return EstadoVazio(
      icone: naoLiberado ? Icons.lock_outline : Icons.cloud_off_outlined,
      titulo: naoLiberado ? 'Ainda sem acesso à escola' : 'Sem conexão',
      texto: _pairing.erroDeConexao,
      acao: FilledButton.icon(
        onPressed: _pairing.tentarNovamente,
        icon: const Icon(Icons.refresh),
        label: const Text('Tentar de novo'),
      ),
    );
  }

  Widget _conteudo(List<PcSession> pcs) {
    final aula = _pairing.aulaAtiva;
    final faixas = [
      FaixaEstadoTurma(pairing: _pairing, tipo: TipoEntrega.trava),
      FaixaEstadoTurma(pairing: _pairing, tipo: TipoEntrega.prova),
      FaixaEntrega(pairing: _pairing),
    ];
    if (aula && _grade) {
      return Column(
        children: [
          _acoesDaAula(compacto: true),
          ...faixas,
          Expanded(
            child: GradeTelas(
              pairing: _pairing,
              visivel: widget.visivel,
              onAbrirPc: _abrirDevicePage,
            ),
          ),
        ],
      );
    }
    final recados = _pairing.recadosCount;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (aula) _acoesDaAula() else ...[_comecarAula(), _acoesForaDaAula()],
        ...faixas,
        if (recados > 0) _cartaoRecados(recados),
        if (pcs.isEmpty) _semComputadores() else ..._listaPcs(pcs),
      ],
    );
  }

  // ---- Cartões do alto ---------------------------------------------------------

  /// Ações da turma; [compacto] (com as telas ao vivo) deixa só uma linha,
  /// para sobrar espaço para a grade.
  Widget _acoesDaAula({bool compacto = false}) {
    final trava = _pairing.travaLigada;
    final prova = _pairing.provaLigada;
    final chamada = BotaoDeAcao(
      icone: Icons.how_to_reg_outlined,
      rotulo: 'Chamada',
      dica: 'Fazer chamada',
      onPressed: () => Navigator.of(context).push(rotaChamada(_pairing)),
    );
    final telas = BotaoDeAcao(
      icone: _grade ? Icons.view_list_outlined : Icons.grid_view,
      rotulo: _grade ? 'Lista' : 'Telas',
      dica: _grade ? 'Voltar para a lista' : 'Ver as telas ao vivo',
      ligado: _grade,
      onPressed: _alternarGrade,
    );
    final mensagem = BotaoDeAcao(
      icone: Icons.forum_outlined,
      rotulo: 'Mensagem',
      dica: 'Mensagem para a turma',
      onPressed: () => mostrarSheetMensagemTurma(context, _pairing),
    );
    final travar = BotaoDeAcao(
      icone: trava ? Icons.lock_open : Icons.lock_outline,
      rotulo: trava ? 'Destravar' : 'Travar',
      dica: trava ? 'Destravar as telas da turma' : 'Travar as telas da turma',
      ligado: trava,
      onPressed: () =>
          trava ? destravarTurma(context, _pairing) : travarComSheet(context, _pairing),
    );
    final abrirSite = BotaoDeAcao(
      icone: Icons.open_in_browser,
      rotulo: 'Abrir site',
      dica: 'Abrir um site na turma',
      onPressed: _abrirSiteNaTurma,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Cartao(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GradeDeAcoes(
          acoes: compacto
              ? [telas, travar, abrirSite, mensagem]
              : [
                  chamada,
                  travar,
                  BotaoDeAcao(
                    icone: prova ? Icons.fact_check : Icons.fact_check_outlined,
                    rotulo: prova ? 'Prova ligada' : 'Prova',
                    dica: prova ? 'Desligar o modo prova' : 'Modo prova: só sites permitidos',
                    ligado: prova,
                    onPressed: () => alternarProva(
                      context,
                      _pairing,
                      onEditarSites: _irParaSitesDaProva,
                    ),
                  ),
                  telas,
                  abrirSite,
                  mensagem,
                  BotaoDeAcao(
                    icone: Icons.power_settings_new,
                    rotulo: 'Desligar',
                    dica: 'Sair da conta, reiniciar ou desligar os computadores',
                    onPressed: () => mostrarSheetEnergia(context, _pairing),
                  ),
                  BotaoDeAcao(
                    icone: Icons.stop_circle_outlined,
                    rotulo: 'Encerrar',
                    dica: 'Encerrar a aula',
                    tom: Tom.perigo,
                    onPressed: _encerrarAula,
                  ),
                ],
        ),
      ),
    );
  }

  Widget _comecarAula() {
    final t = Theme.of(context);
    final turmas = _pairing.turmas;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Cartao(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_outline, color: t.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Começar uma aula', style: t.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              turmas.isEmpty
                  ? 'Cadastre a primeira turma para começar.'
                  : 'Escolha a turma. A chamada abre em seguida.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (turmas.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: widget.onIrParaTurmas,
                  icon: const Icon(Icons.add),
                  label: const Text('Cadastrar turma'),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final turma in turmas)
                    OutlinedButton(
                      onPressed: () => _iniciarAula(turma.nome),
                      child: Text(turma.nome),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _acoesForaDaAula() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Cartao(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GradeDeAcoes(
          acoes: [
            BotaoDeAcao(
              icone: Icons.open_in_browser,
              rotulo: 'Abrir site',
              dica: 'Abrir um site em todos os computadores',
              onPressed: _abrirSiteNaTurma,
            ),
            BotaoDeAcao(
              icone: Icons.qr_code_scanner,
              rotulo: 'Conectar',
              dica: 'Conectar um computador',
              onPressed: _abrirScanner,
            ),
            if (_pairing.workspaceAtivo)
              BotaoDeAcao(
                icone: Icons.photo_camera_front_outlined,
                rotulo: 'Fotos de entrada',
                dica: 'Fotos de início de sessão',
                onPressed: _abrirFotosDeEntrada,
              ),
            BotaoDeAcao(
              icone: Icons.power_settings_new,
              rotulo: 'Desligar',
              dica: 'Sair da conta, reiniciar ou desligar os computadores',
              onPressed: () => mostrarSheetEnergia(context, _pairing),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoRecados(int n) {
    final t = Theme.of(context);
    final c = cores(context);
    final pedidos = _pairing.pedidosPendentes.length;
    final maos = _pairing.maosLevantadas.length;
    final partes = [
      if (pedidos > 0) pedidos == 1 ? '1 pedido de liberação' : '$pedidos pedidos de liberação',
      if (maos > 0) maos == 1 ? '1 mão levantada' : '$maos mãos levantadas',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Cartao(
        cor: c.atencaoBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: () => abrirRecados(context, _pairing),
        child: Row(
          children: [
            Icon(Icons.inbox_outlined, color: c.atencao),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 1 ? '1 recado' : '$n recados',
                    style: t.textTheme.titleSmall?.copyWith(color: c.atencao),
                  ),
                  if (partes.isNotEmpty)
                    Text(
                      partes.join(' · '),
                      style: t.textTheme.bodySmall?.copyWith(color: c.atencao),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.atencao),
          ],
        ),
      ),
    );
  }

  Widget _semComputadores() {
    return EstadoVazio(
      icone: Icons.devices_other,
      titulo: 'Nenhum computador conectado',
      texto: 'Conecte cada computador uma vez, lendo o QR Code que ele mostra. '
          'Depois ele conecta sozinho, até em outra rede Wi-Fi.',
      acao: FilledButton.icon(
        onPressed: _abrirScanner,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Conectar computador'),
      ),
    );
  }

  // ---- Lista de computadores -----------------------------------------------------

  // Seções: telão → na aula → aulas de colegas → disponíveis → desligados
  // (desligados escondidos atrás de "Mostrar" quando há mais seções).
  List<Widget> _listaPcs(List<PcSession> pcs) {
    final porId = {for (final s in pcs) s.deviceId: s};
    final secoes = secoesDaHome([
      for (final s in pcs)
        (
          id: s.deviceId,
          nome: _pairing.nomeDe(s),
          online: _pairing.isOnline(s),
          telao: _pairing.ehPcProfessor(s.deviceId),
          aula: _pairing.aulaDoPc(s.deviceId),
        ),
    ]);
    final temMaisSecoes = secoes.length > 1;
    final children = <Widget>[];
    for (final secao in secoes) {
      final ids = [for (final id in secao.ids) if (porId[id] != null) id];
      if (ids.isEmpty) continue;
      final esconder = secao.colapsavel && temMaisSecoes && !_mostrarTodos;
      final titulo = secao.titulo == null ? null : '${secao.titulo} · ${ids.length}';
      if (esconder) {
        children.add(
          TituloDeSecao(
            titulo!,
            acao: TextButton(
              onPressed: () => setState(() => _mostrarTodos = true),
              child: const Text('Mostrar'),
            ),
          ),
        );
        continue;
      }
      children.add(
        titulo == null
            ? const SizedBox(height: 12)
            : TituloDeSecao(
                titulo,
                acao: secao.colapsavel && temMaisSecoes
                    ? TextButton(
                        onPressed: () => setState(() => _mostrarTodos = false),
                        child: const Text('Esconder'),
                      )
                    : null,
              ),
      );
      children.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                if (i > 0) const Divider(indent: 74),
                _linhaDoPc(porId[ids[i]]!),
              ],
            ],
          ),
        ),
      );
    }
    return children;
  }

  Widget _linhaDoPc(PcSession s) {
    final t = Theme.of(context);
    final c = cores(context);
    final on = _pairing.isOnline(s);
    final nome = _pairing.nomeDe(s);
    final numero = _pairing.numeroDe(s.deviceId);
    final telao = _pairing.ehPcProfessor(s.deviceId);
    final aluno = !telao && _pairing.aulaAtiva ? _pairing.alunoDe(s.deviceId) : null;
    final ativa = s.abaAtiva;
    final alerta = on && !telao ? s.alerta : null;
    final liberados = !telao && _pairing.liberacoesDe(s.deviceId).isNotEmpty;

    // O nome do computador só aparece embaixo se não for o "Unidade N" que o
    // número ao lado já diz.
    final nomeExtra = aluno != null && nome != 'Unidade $numero' ? nome : null;
    final site = ativa == null ? null : (ativa.title.isEmpty ? dominioDe(ativa.url) : ativa.title);
    final String linha;
    if (telao) {
      linha = on ? 'Computador do Professor' : 'Computador do Professor · desligado';
    } else if (!on) {
      linha = [if (nomeExtra != null) nomeExtra, 'Desligado'].join(' · ');
    } else if (alerta != null) {
      linha = 'Alerta: $alerta';
    } else {
      linha = [
        if (nomeExtra != null) nomeExtra,
        site ?? 'Ligado',
        if (liberados) 'sites liberados',
      ].join(' · ');
    }

    // Situação do aluno à vista: tela travada, mão levantada, mensagens novas
    // (mão e mensagens só dos PCs que não estão na aula de outro professor).
    final meuRecado = !telao && _pairing.professorQueTravou(s.deviceId) == null;
    final naoLidas = meuRecado ? _pairing.naoLidasDe(s.deviceId) : 0;
    final sinais = <Widget>[
      if (!telao) ...chipsDeTrava(context, _pairing, s.deviceId),
      if (meuRecado && _pairing.maoLevantada(s.deviceId))
        Selo(
          'Mão levantada',
          icone: Icons.back_hand,
          tom: Tom.atencao,
          onTap: () => abrirConversa(context, _pairing, s.deviceId),
        ),
      if (naoLidas > 0)
        Selo(
          naoLidas == 1 ? '1 mensagem nova' : '$naoLidas mensagens novas',
          icone: Icons.chat_bubble,
          tom: Tom.primario,
          onTap: () => abrirConversa(context, _pairing, s.deviceId),
        ),
    ];

    final texto = Text(
      linha,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.textTheme.bodySmall?.copyWith(
        color: alerta != null ? c.alertaFg : null,
        fontWeight: alerta != null ? FontWeight.w600 : null,
      ),
    );

    return InkWell(
      onTap: () => _abrirDevicePage(s.deviceId),
      onLongPress: () => _acoesDoPc(s.deviceId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            SeloDaUnidade(numero: numero, estado: estadoDoPc(_pairing, s)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aluno ?? nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      color: on ? null : t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  texto,
                  if (sinais.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: sinais),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Ações do computador',
              color: t.colorScheme.onSurfaceVariant,
              onPressed: () => _acoesDoPc(s.deviceId),
            ),
          ],
        ),
      ),
    );
  }

  static String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _alunos(int n) => n == 1 ? '1 aluno' : '$n alunos';

  static String _computadores(int n) => n == 1 ? '1 computador' : '$n computadores';
}
