// Aba Aula: a tela de trabalho do professor — lista de PCs em destaque e a
// sessão de aula; "abrir um site" fica na barra do topo. Nada aqui usa cor hardcoded
// (ver theme.dart / CoresAula).

import 'package:flutter/material.dart';

import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import 'device_page.dart';
import 'home_sections.dart';
import 'scan_page.dart';
import 'theme.dart';

class AulaPage extends StatefulWidget {
  const AulaPage({super.key, required this.pairing, required this.onIrParaSites});

  final PairingController pairing;

  /// Navega para a aba Sites (editar favoritos/regras).
  final VoidCallback onIrParaSites;

  @override
  State<AulaPage> createState() => _AulaPageState();
}

class _AulaPageState extends State<AulaPage> {
  PairingController get _pairing => widget.pairing;

  /// Lista: offline colapsado atrás de "Ver todos" quando há online.
  bool _mostrarTodos = false;

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

  Future<bool> _confirmar({
    required String titulo,
    required String mensagem,
    required String acao,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(acao),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ---- Sessão de aula --------------------------------------------------------------

  Future<void> _iniciarAula() async {
    final turmas = _pairing.turmas;
    if (turmas.isEmpty) {
      _snack('Cadastre uma turma primeiro, na aba Turmas.');
      return;
    }
    final escolhida = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Iniciar aula com qual turma?')),
            const Divider(height: 1),
            for (final t in turmas)
              ListTile(
                leading: const Icon(Icons.school),
                title: Text(t.nome),
                subtitle: Text('${t.alunos.length} aluno(s)'),
                onTap: () => Navigator.pop(ctx, t.nome),
              ),
          ],
        ),
      ),
    );
    if (escolhida != null) {
      await _pairing.iniciarAula(escolhida);
      _snack('Aula iniciada: $escolhida. Vincule os alunos pelo botão de '
          'cada PC.');
    }
  }

  Future<void> _encerrarAula() async {
    final n = _pairing.pcsAlvoCount; // só os vinculados
    final ok = await _confirmar(
      titulo: 'Encerrar aula',
      mensagem: 'Fecha o NAVEGADOR (todas as janelas) em $n PC(s) com aluno '
          'e limpa os vínculos de alunos desta aula.',
      acao: 'Encerrar',
    );
    if (ok) {
      await _pairing.encerrarAula();
      _snack('Aula encerrada — navegador fechado em $n PC(s).');
    }
  }

  Future<void> _vincularAluno(String deviceId) async {
    final disponiveis = _pairing.alunosDisponiveis;
    final atual = _pairing.alunoDe(deviceId);
    final pc = _pairing.pcPorId(deviceId);
    final ligado = pc != null && _pairing.isOnline(pc);
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                atual == null
                    ? 'Quem está neste PC?'
                    : 'Neste PC: $atual — trocar por:',
              ),
            ),
            const Divider(height: 1),
            if (ligado)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Não sei quem é — tirar foto'),
                onTap: () => Navigator.pop(ctx, ' foto'),
              ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Cadastrar aluno novo'),
              onTap: () => Navigator.pop(ctx, ' novo'),
            ),
            if (atual != null)
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('Tirar aluno do PC'),
                onTap: () => Navigator.pop(ctx, ' remover'),
              ),
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
          ],
        ),
      ),
    );
    if (escolhido == null) return;
    if (escolhido == ' foto') {
      if (!mounted) return;
      // Foto pra identificar, e volta pra lista com a resposta na cabeça.
      await mostrarImagemDoPc(
        context,
        _pairing,
        deviceId,
        _pairing.nomeDe(pc!),
        tela: false,
      );
      if (mounted) await _vincularAluno(deviceId);
      return;
    }
    if (escolhido == ' novo') {
      await _cadastrarEVincular(deviceId);
    } else if (escolhido == ' remover') {
      await _pairing.desvincularAluno(deviceId);
    } else {
      // Workspace: o PC pode estar preso na aula de outro professor.
      final erro = await _pairing.vincularAluno(deviceId, escolhido);
      if (erro != null) _snack(erro);
    }
  }

  Future<void> _cadastrarEVincular(String deviceId) async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo aluno'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome do aluno',
            hintText: 'ex.: William',
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
            child: const Text('Cadastrar'),
          ),
        ],
      ),
    );
    if (nome == null || nome.trim().isEmpty) return;
    final erro = await _pairing.cadastrarEVincularAluno(deviceId, nome);
    if (mounted) _snack(erro ?? '${nome.trim()} está usando este PC.');
  }

  // Menu do PC (⋮ e long-press): as mesmas 4 opções em todas as linhas; o
  // resto vive no ⋮ da tela do PC.
  void _menuPc(PcSession s, String nome) {
    final on = _pairing.isOnline(s);
    final ehProfessor = _pairing.ehPcProfessor(s.deviceId);
    final travadoPor = _pairing.professorQueTravou(s.deviceId);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(_pairing.alunoDe(s.deviceId) ?? nome),
              subtitle: ehProfessor ? const Text('Computador do Professor') : null,
            ),
            const Divider(height: 1),
            if (!ehProfessor)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Desbloquear sites deste PC'),
                subtitle:
                    travadoPor == null ? null : Text('Está na aula de $travadoPor'),
                enabled: travadoPor == null,
                onTap: () {
                  Navigator.pop(ctx);
                  mostrarSheetLiberarSites(context, _pairing, s.deviceId);
                },
              ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Enviar mensagem'),
              enabled: on,
              onTap: () {
                Navigator.pop(ctx);
                mostrarDialogoMensagem(context, _pairing, s.deviceId, nome);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ver quem está no PC'),
              enabled: on,
              onTap: () {
                Navigator.pop(ctx);
                mostrarImagemDoPc(context, _pairing, s.deviceId, nome, tela: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.screenshot_monitor_outlined),
              title: const Text('Ver a tela do PC'),
              subtitle: const Text('só nos PCs com Celita OS'),
              enabled: on,
              onTap: () {
                Navigator.pop(ctx);
                mostrarImagemDoPc(context, _pairing, s.deviceId, nome, tela: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- Build -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pcs = _pairing.pcs;
    final online = pcs.where(_pairing.isOnline).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Aula'),
        actions: [
          _chipOnline(online),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Abrir um site na turma',
            onPressed: _abrirSiteNaTurma,
          ),
        ],
      ),
      body: _pairing.iniciando
          ? const Center(child: CircularProgressIndicator())
          : _pairing.erroDeConexao != null
              ? _erroView()
              : _conteudo(pcs),
    );
  }

  Widget _chipOnline(int online) {
    final c = cores(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 8,
              color: online > 0 ? c.online : c.offline,
            ),
            const SizedBox(width: 6),
            Text('$online online'),
          ],
        ),
      ),
    );
  }

  Widget _erroView() {
    final naoLiberado = _pairing.naoLiberadoNaEscola;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              naoLiberado ? Icons.lock_outline : Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(_pairing.erroDeConexao!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pairing.tentarNovamente,
              icon: const Icon(Icons.refresh),
              label: Text(naoLiberado ? 'Tentar de novo' : 'Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  // Banner da aula ativa (turma + progresso dos vínculos + encerrar).
  Widget _bannerAula() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.school, size: 20, color: scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aula: ${_pairing.turmaDaAula} · '
                '${_pairing.totalVinculados}/${_pairing.totalAlunosDaTurma} '
                'alunos com PC',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _encerrarAula,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Encerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conteudo(List<PcSession> pcs) {
    return Column(
      children: [
        if (_pairing.aulaAtiva)
          _bannerAula()
        else
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Sem aula em andamento'),
              trailing: FilledButton.tonal(
                onPressed: _iniciarAula,
                child: const Text('Iniciar aula'),
              ),
            ),
          ),
        Expanded(
          child: pcs.isEmpty ? _vazio() : _listaPcs(pcs),
        ),
      ],
    );
  }

  // Seções: telão → minha aula → aulas de colegas → disponíveis → offline
  // (offline colapsado atrás de "Ver todos" quando há mais seções).
  Widget _listaPcs(List<PcSession> pcs) {
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
    var ocultos = 0;
    for (final secao in secoes) {
      final esconder = secao.colapsavel && temMaisSecoes && !_mostrarTodos;
      if (esconder) {
        ocultos += secao.ids.length;
        continue;
      }
      if (secao.titulo != null) children.add(_headerSecao(secao.titulo!));
      for (final id in secao.ids) {
        final s = porId[id];
        if (s == null) continue;
        children
          ..add(_pcCard(s))
          ..add(const Divider(height: 0.5));
      }
    }
    final temColapsavel =
        temMaisSecoes && secoes.any((s) => s.colapsavel && s.ids.isNotEmpty);
    if (temColapsavel) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _mostrarTodos = !_mostrarTodos),
              icon: Icon(
                _mostrarTodos ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _mostrarTodos ? 'Ocultar offline' : 'Ver todos (+$ocultos offline)',
              ),
            ),
          ),
        ),
      );
    }

    return ListView(padding: EdgeInsets.zero, children: children);
  }

  /// Header de seção flat (estilo IG): label pequeno em destaque.
  Widget _headerSecao(String titulo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }

  Widget _vazio() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            const Text(
              'Nenhum PC pareado ainda.\n\n'
              'Em cada Chromebook, abra o popup da extensão Controle de Aula '
              'e escaneie o QR exibido.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _abrirScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Conectar um Chromebook'),
            ),
            const SizedBox(height: 12),
            Text(
              'Você conecta cada PC uma única vez; depois disso ele '
              'conecta sozinho, mesmo em outra rede Wi-Fi.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pcCard(PcSession s) {
    final scheme = Theme.of(context).colorScheme;
    final c = cores(context);
    final on = _pairing.isOnline(s);
    final nome = _pairing.nomeDe(s);
    final rotulo = _pairing.rotuloDe(s);
    final ehProfessor = _pairing.ehPcProfessor(s.deviceId);
    final aluno = !ehProfessor && _pairing.aulaAtiva
        ? _pairing.alunoDe(s.deviceId)
        : null;
    final ativa = s.abaAtiva;
    final alerta = on && !ehProfessor ? s.alerta : null;

    final String subtitulo;
    if (ehProfessor) {
      subtitulo = 'Computador do Professor · ${on ? 'online' : 'offline'}';
    } else {
      final prefixo = aluno != null ? '$rotulo · ' : '';
      final liberados = _pairing.liberacoesDe(s.deviceId).isNotEmpty
          ? ' · sites liberados'
          : '';
      if (!on) {
        subtitulo = '${prefixo}offline$liberados';
      } else if (ativa == null) {
        subtitulo = '${prefixo}online — sem dados de abas$liberados';
      } else {
        final titulo = ativa.title.isEmpty ? '(sem título)' : ativa.title;
        final linha = '$prefixo$titulo\n${dominioDe(ativa.url)}$liberados';
        subtitulo = alerta != null ? '⚠ Alerta: $alerta\n$linha' : linha;
      }
    }

    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: alerta != null
          ? c.alertaBg
          : on
              ? (ehProfessor
                  ? scheme.primaryContainer
                  : c.online.withValues(alpha: 0.15))
              : scheme.surfaceContainerHighest,
      child: Icon(
        ehProfessor
            ? Icons.co_present
            : alerta != null
                ? Icons.warning_amber
                : aluno != null
                    ? Icons.person
                    : Icons.computer,
        color: alerta != null
            ? c.alertaFg
            : on
                ? (ehProfessor ? scheme.onPrimaryContainer : c.online)
                : c.offline,
      ),
    );

    // Escolher/Trocar aluno sempre à vista durante a aula (menos no telão e
    // em PC preso na aula de outro professor).
    final mostrarVincular = !ehProfessor &&
        _pairing.aulaAtiva &&
        _pairing.professorQueTravou(s.deviceId) == null;

    final conteudo = ListTile(
      leading: avatar,
      title: Text(
        aluno ?? rotulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitulo,
        maxLines: alerta != null ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: alerta != null ? TextStyle(color: c.alertaFg) : null,
      ),
      isThreeLine: on && ativa != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mostrarVincular)
            IconButton(
              icon: Icon(
                aluno == null ? Icons.person_add_alt : Icons.manage_accounts,
                color: scheme.primary,
              ),
              tooltip: aluno == null ? 'Escolher aluno' : 'Trocar aluno',
              onPressed: () => _vincularAluno(s.deviceId),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Opções do PC',
            onPressed: () => _menuPc(s, nome),
          ),
        ],
      ),
    );

    // Flat (sem card): fundo = scaffold; o alerta aparece pelo avatar/subtítulo.
    return InkWell(
      onTap: () => _abrirDevicePage(s.deviceId),
      onLongPress: () => _menuPc(s, nome),
      child: on ? conteudo : Opacity(opacity: 0.55, child: conteudo),
    );
  }
}
