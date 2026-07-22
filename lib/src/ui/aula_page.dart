// Aba Aula: a tela de trabalho do professor — lista de PCs em destaque,
// comando de site compacto e a sessão de aula. Nada aqui usa cor hardcoded
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
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://');

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
    _urlCtrl.dispose();
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

  // ---- Comandos de turma ---------------------------------------------------------

  // Alvo dos comandos de turma (só vinculados durante a aula). Retorna -1 e
  // avisa quando não há ninguém pra receber.
  int? _alvoOuAviso() {
    final n = _pairing.pcsAlvoCount;
    if (n == 0) {
      _snack(
        _pairing.aulaAtiva
            ? 'Nenhum PC vinculado a aluno nesta aula.'
            : 'Nenhum PC conectado ainda.',
      );
      return null;
    }
    return n;
  }

  void _abrirEmTodos() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final n = _alvoOuAviso();
    if (n == null) return;
    _pairing.abrirEmTodos(url);
    _snack('Enviado para $n PC(s).');
  }

  void _abrirEm(String deviceId, String label) {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _snack('Digite/escolha um site primeiro.');
      return;
    }
    _pairing.abrirEm(deviceId, url);
    _snack('Enviado para $label.');
  }

  Future<void> _fecharSiteEmTodos() async {
    final dominio = dominioDe(_urlCtrl.text.trim());
    if (dominio.isEmpty || !dominio.contains('.')) {
      _snack('Digite/escolha um site primeiro.');
      return;
    }
    final n = _alvoOuAviso();
    if (n == null) return;
    final ok = await _confirmar(
      titulo: 'Fechar site na turma',
      mensagem: 'Fechar todas as abas de $dominio em $n PC(s)?',
      acao: 'Fechar',
    );
    if (ok) {
      _pairing.fecharSiteEmTodos(dominio);
      _snack('Fechando $dominio em $n PC(s).');
    }
  }

  Future<void> _fecharTodasAsAbas() async {
    final n = _alvoOuAviso();
    if (n == null) return;
    final ok = await _confirmar(
      titulo: 'Fechar todas as abas',
      mensagem:
          'Fechar TODAS as abas em $n PC(s)? Cada um fica com uma aba vazia.',
      acao: 'Fechar tudo',
    );
    if (ok) {
      _pairing.fecharTodasAsAbasEmTodos();
      _snack('Fechando todas as abas em $n PC(s).');
    }
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
      mensagem: 'Fecha o NAVEGADOR (todas as janelas) em $n PC(s) vinculado(s) '
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
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Cadastrar e vincular novo aluno'),
              onTap: () => Navigator.pop(ctx, ' novo'),
            ),
            if (atual != null)
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('Remover vínculo'),
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
            child: const Text('Cadastrar e vincular'),
          ),
        ],
      ),
    );
    if (nome == null || nome.trim().isEmpty) return;
    final erro = await _pairing.cadastrarEVincularAluno(deviceId, nome);
    if (mounted) _snack(erro ?? '${nome.trim()} vinculado a este PC.');
  }

  // Menu do PC (⋮ e long-press): tudo que era gesto escondido, agora visível.
  void _menuPc(PcSession s, String nome) {
    final on = _pairing.isOnline(s);
    final ehProfessor = _pairing.ehPcProfessor(s.deviceId);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(_pairing.alunoDe(s.deviceId) ?? nome),
              subtitle: ehProfessor ? const Text('PC do professor') : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Abrir o site só neste PC'),
              enabled: on,
              onTap: () {
                Navigator.pop(ctx);
                _abrirEm(s.deviceId, _pairing.alunoDe(s.deviceId) ?? nome);
              },
            ),
            if (_pairing.aulaAtiva && !ehProfessor)
              ListTile(
                leading: const Icon(Icons.person_pin_circle_outlined),
                title: Text(
                  _pairing.alunoDe(s.deviceId) == null
                      ? 'Vincular aluno'
                      : 'Trocar/remover aluno',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _vincularAluno(s.deviceId);
                },
              ),
            if (!ehProfessor)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Desbloquear sites deste PC'),
                subtitle: _pairing.aulaAtiva
                    ? null
                    : const Text('exige uma aula em andamento'),
                onTap: () {
                  Navigator.pop(ctx);
                  mostrarSheetLiberarSites(context, _pairing, s.deviceId);
                },
              ),
            ListTile(
              leading: Icon(ehProfessor ? Icons.co_present : Icons.co_present_outlined),
              title: Text(
                ehProfessor
                    ? 'Desmarcar PC do professor'
                    : 'Marcar como PC do professor',
              ),
              subtitle: ehProfessor
                  ? null
                  : const Text('sem bloqueios/monitoramento; recebe os avisos'),
              onTap: () {
                Navigator.pop(ctx);
                _pairing.marcarPcProfessor(ehProfessor ? null : s.deviceId);
                _snack(
                  ehProfessor
                      ? '$nome voltou a ser PC de aluno.'
                      : '$nome agora é o PC do professor.',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renomear unidade'),
              onTap: () {
                Navigator.pop(ctx);
                mostrarDialogoRenomear(context, _pairing, s.deviceId, nome);
              },
            ),
            ListTile(
              leading: const Icon(Icons.pin),
              title: const Text('Alterar número da unidade'),
              onTap: () {
                Navigator.pop(ctx);
                mostrarDialogoNumeroUnidade(context, _pairing, s.deviceId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tab_unselected),
              title: const Text('Fechar todas as abas deste PC'),
              enabled: on,
              onTap: () {
                Navigator.pop(ctx);
                _pairing.fecharTodasAsAbasEm(s.deviceId);
                _snack('Fechando as abas de $nome.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Esquecer este PC'),
              onTap: () {
                Navigator.pop(ctx);
                confirmarEsquecerPc(context, _pairing, s.deviceId, nome);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _menuFavorito(int indice) {
    final f = _pairing.favoritos[indice];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(f.label),
              subtitle: Text(f.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('Abrir na turma toda'),
              onTap: () {
                Navigator.pop(ctx);
                final n = _pairing.pcs.length;
                _pairing.abrirEmTodos(f.url);
                _snack('Enviado para $n PC(s).');
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text('Fechar ${dominioDe(f.url)} na turma'),
              onTap: () {
                Navigator.pop(ctx);
                _pairing.fecharSiteEmTodos(dominioDe(f.url));
                _snack('Fechando ${dominioDe(f.url)} na turma.');
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
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Parear PC (escanear QR)',
            onPressed: _abrirScanner,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(_pairing.erroDeConexao!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pairing.tentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
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
                'alunos vinculados',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campo + enviar embutido: 1 linha em vez de campo + botão.
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Endereço do site',
                  hintText: 'https://...',
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: 'Abrir na turma toda',
                    onPressed: _abrirEmTodos,
                  ),
                ),
                onSubmitted: (_) => _abrirEmTodos(),
              ),
              if (_pairing.favoritos.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _pairing.favoritos.length; i++) ...[
                        GestureDetector(
                          onLongPress: () => _menuFavorito(i),
                          child: ActionChip(
                            avatar: Icon(
                              Icons.star,
                              size: 16,
                              color: cores(context).favorito,
                            ),
                            label: Text(_pairing.favoritos[i].label),
                            onPressed: () => setState(
                              () => _urlCtrl.text = _pairing.favoritos[i].url,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ActionChip(
                        avatar: const Icon(Icons.edit, size: 16),
                        label: const Text('Editar'),
                        onPressed: widget.onIrParaSites,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _fecharSiteEmTodos,
                      icon: const Icon(Icons.close),
                      label: const Text('Fechar site'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _fecharTodasAsAbas,
                      icon: const Icon(Icons.tab_unselected),
                      label: const Text('Fechar tudo'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
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
              label: const Text('Escanear QR do Chromebook'),
            ),
            const SizedBox(height: 12),
            Text(
              'O pareamento é feito uma única vez por PC; depois disso ele '
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
    final ehProfessor = _pairing.ehPcProfessor(s.deviceId);
    final aluno = !ehProfessor && _pairing.aulaAtiva
        ? _pairing.alunoDe(s.deviceId)
        : null;
    final ativa = s.abaAtiva;
    final alerta = on && !ehProfessor ? s.alerta : null;

    final String subtitulo;
    if (ehProfessor) {
      subtitulo = 'PC do professor · ${on ? 'online' : 'offline'}';
    } else {
      final prefixo = aluno != null ? '$nome · ' : '';
      if (!on) {
        subtitulo = '${prefixo}offline';
      } else if (ativa == null) {
        subtitulo = '${prefixo}online — sem dados de abas';
      } else {
        final titulo = ativa.title.isEmpty ? '(sem título)' : ativa.title;
        final linha = '$prefixo$titulo\n${dominioDe(ativa.url)}';
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

    // Caminho crítico descobrível: PC online sem aluno numa aula ativa.
    final mostrarVincular =
        !ehProfessor && _pairing.aulaAtiva && aluno == null && on;

    final conteudo = ListTile(
      leading: avatar,
      title: Text(
        aluno ?? nome,
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
          // Vincular como ícone (junto do ⋮): PC online sem aluno em aula.
          if (mostrarVincular)
            IconButton(
              icon: Icon(Icons.person_add_alt, color: scheme.primary),
              tooltip: 'Vincular aluno',
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DevicePage(pairing: _pairing, deviceId: s.deviceId),
        ),
      ),
      onLongPress: () => _menuPc(s, nome),
      child: on ? conteudo : Opacity(opacity: 0.55, child: conteudo),
    );
  }
}
