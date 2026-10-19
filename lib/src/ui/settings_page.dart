// Aba Ajustes, em grupos: computadores (conectar, atualizar, papel de parede,
// exportar), escola, conta e professor, preferências e versão.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../cloud/archive_store.dart';
import '../pairing/pairing_controller.dart';
import 'componentes.dart';
import 'exportar_historico.dart';
import 'scan_page.dart';
import 'school_members_page.dart';
import 'settings_controller.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.pairing, required this.settings});

  final PairingController pairing;
  final SettingsController settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  // Consulta o sistema ao abrir e ao voltar ao app, não a cada rebuild.
  bool _notificacoesBloqueadas = false;

  Future<void> _checarNotificacoes() async {
    final liberadas = await widget.pairing.notificacoes?.habilitadasNoSistema();
    if (mounted) setState(() => _notificacoesBloqueadas = liberadas == false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checarNotificacoes();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checarNotificacoes();
    widget.settings.addListener(_onChange);
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onChange);
    widget.pairing.removeListener(_onChange);
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

  Future<void> _editarNome() async {
    final ctrl = TextEditingController(text: widget.settings.nomeProfessor);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome do professor'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome',
            hintText: 'ex.: Prof. Mano',
            helperText: 'Aparece no popup da extensão. PCs já pareados '
                'continuam mostrando o nome antigo até serem pareados de novo.',
            helperMaxLines: 3,
          ),
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
    if (novo == null) return;
    await widget.settings.setNomeProfessor(novo);
    widget.pairing.atualizarNomeProfessor(novo);
    _snack('Nome salvo.');
  }

  Future<String?> _pedirPin({required String titulo, required String acao}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: 'PIN de backup',
            helperText: 'Mínimo 6 dígitos. Guarde bem — sem ele o backup '
                'não abre em outro celular.',
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().length >= 6) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: Text(acao),
          ),
        ],
      ),
    );
  }

  Future<void> _criarWorkspace() async {
    if (!widget.pairing.logadoComGoogle) {
      _snack('Entre com o Google primeiro (seção Conta, abaixo).');
      return;
    }
    _snack('Criando a escola…');
    final erro = await widget.pairing.criarWorkspace();
    if (!mounted) return;
    _snack(erro ?? 'Escola criada — seus computadores e dados agora são compartilhados.');
    setState(() {});
  }

  Future<void> _entrarWorkspace() async {
    // A chave local é sobrescrita pela da escola: PCs pareados com a chave
    // própria deixam de responder (precisam re-parear).
    if (widget.pairing.pcs.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Entrar na escola'),
          content: Text(
            'Este celular tem ${_computadores(widget.pairing.pcs.length)} '
            'conectados pela sua conta pessoal. Ao entrar, eles vão precisar '
            'reconectar (tocar em "Desvincular" no computador e ler o código de '
            'novo). Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _snack('Entrando na escola…');
    final erro = await widget.pairing.entrarNoWorkspace();
    if (!mounted) return;
    _snack(erro ?? 'Pronto! Você entrou na escola.');
    setState(() {});
  }

  Future<void> _entrarComGoogle() async {
    _snack('Entrando com o Google…');
    final r = await widget.pairing.entrarComGoogle();
    if (!mounted) return;
    if (r == 'linked') {
      final pin =
          await _pedirPin(titulo: 'Criar PIN de backup', acao: 'Ativar backup');
      if (pin == null || !mounted) return;
      await widget.pairing.ativarBackup(pin);
      if (mounted) _snack('Backup ativado. Seus dados vão para a nuvem.');
    } else if (r == 'switched') {
      final tem = await widget.pairing.temBackupNaNuvem();
      if (!mounted) return;
      if (tem) {
        await _restaurar();
      } else {
        final pin = await _pedirPin(
          titulo: 'Criar PIN de backup',
          acao: 'Ativar backup',
        );
        if (pin == null || !mounted) return;
        await widget.pairing.ativarBackup(pin);
        if (mounted) _snack('Backup ativado.');
      }
    } else if (r.startsWith('erro:') &&
        !r.toLowerCase().contains('cancel')) {
      debugPrint('[CdA] entrar com Google: ${r.substring(5)}');
      _snack('Não foi possível entrar com o Google. Tente de novo.');
    }
    if (mounted) setState(() {});
  }

  Future<void> _restaurar() async {
    final pin = await _pedirPin(titulo: 'Restaurar backup', acao: 'Restaurar');
    if (pin == null || !mounted) return;
    _snack('Restaurando…');
    final erro = await widget.pairing.restaurarBackup(pin);
    if (!mounted) return;
    if (erro == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup restaurado'),
          content: const Text(
            'Feche e abra o app para carregar os dados restaurados '
            '(computadores, histórico, turmas).',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    } else {
      _snack(erro);
    }
  }

  Future<void> _escolherPapelDeParede() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (img == null || !mounted) return;
    final n = widget.pairing.pcs.length;
    final ok = await confirmar(
      context,
      titulo: 'Papel de parede',
      mensagem: 'Aplicar esta imagem em ${_computadores(n)}? Os que estiverem '
          'desligados trocam quando ligarem.',
      acao: 'Aplicar',
    );
    if (!ok) return;
    try {
      await widget.pairing.definirPapelDeParede(await img.readAsBytes());
    } on ArgumentError {
      _snack('A imagem é grande demais. Escolha uma com menos de 4 MB.');
      return;
    }
    _snack('Papel de parede enviado para ${_computadores(n)}.');
  }

  static String _computadores(int n) => n == 1 ? '1 computador' : '$n computadores';

  Future<void> _atualizarDesatualizados() async {
    final n = await widget.pairing.atualizarDesatualizados();
    _snack(
      n == 1
          ? '1 computador vai baixar e instalar a atualização.'
          : '$n computadores vão baixar e instalar a atualização.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairing = widget.pairing;
    final velhos = pairing.desatualizadosOnline;
    final maisNova = pairing.versaoPublicada;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          GrupoDeOpcoes(
            titulo: 'Computadores',
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Conectar computador'),
                subtitle: const Text('Ler o QR Code do computador ou do app do professor'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ScanPage(pairing: pairing)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('Atualizar os desatualizados'),
                subtitle: Text(
                  maisNova == null
                      ? 'Verificando a versão mais nova do Celita OS…'
                      : velhos.isEmpty
                          ? 'Todos os ligados estão na versão mais nova ($maisNova).'
                          : '${_computadores(velhos.length)} '
                              '${velhos.length == 1 ? 'ligado está' : 'ligados estão'} '
                              'numa versão antiga. A mais nova é a $maisNova.',
                ),
                enabled: velhos.isNotEmpty,
                onTap: _atualizarDesatualizados,
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Papel de parede'),
                subtitle: Text(
                  pairing.wallpaperHash == null
                      ? 'Uma imagem em todos os computadores, até nos desligados'
                      : 'Imagem aplicada. Toque para trocar.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _escolherPapelDeParede,
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Exportar histórico'),
                subtitle: Text(
                  pairing.workspaceAtivo
                      ? 'Planilha com os sites visitados, de 1 a $kArchiveDays dias'
                      : 'O histórico guardado existe só nos computadores da escola.',
                ),
                enabled: pairing.workspaceAtivo,
                onTap: () => exportarHistorico(context, pairing),
              ),
            ],
          ),
          GrupoDeOpcoes(
            titulo: 'Escola',
            children: [
              if (pairing.workspaceAtivo) ...[
                const ListTile(
                  leading: Icon(Icons.school_outlined),
                  title: Text('Escola conectada'),
                  subtitle: Text(
                    'Computadores, turmas, regras e histórico compartilhados '
                    'entre os professores.',
                  ),
                ),
                if (pairing.souFundador)
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Professores da escola'),
                    subtitle: const Text('Quem pode entrar na escola pelo app'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SchoolMembersPage(emailFundador: pairing.emailGoogle),
                      ),
                    ),
                  ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('Entrar na escola'),
                  subtitle: const Text(
                    'Com a conta Google: você passa a ver os computadores e as '
                    'turmas da escola.',
                  ),
                  onTap: _entrarWorkspace,
                ),
                ListTile(
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Criar a escola'),
                  subtitle: const Text(
                    'Uma vez só, pelo primeiro professor: seus computadores e '
                    'dados viram os da escola.',
                  ),
                  onTap: _criarWorkspace,
                ),
              ],
            ],
          ),
          GrupoDeOpcoes(
            titulo: 'Conta',
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Nome do professor'),
                subtitle: Text(widget.settings.nomeProfessor),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _editarNome,
              ),
              if (!pairing.logadoComGoogle)
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Entrar com o Google'),
                  subtitle: const Text('Guarda seus dados na nuvem para trocar de celular depois.'),
                  onTap: _entrarComGoogle,
                )
              else ...[
                ListTile(
                  leading: Icon(
                    pairing.backupAtivo ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  ),
                  title: Text(pairing.emailGoogle ?? 'Conta Google'),
                  subtitle: Text(
                    pairing.workspaceAtivo
                        ? 'Favoritos e preferências sincronizados na nuvem.'
                        : pairing.backupAtivo
                            ? 'Backup ativo: dados sincronizados na nuvem.'
                            : 'Backup ainda não ativado neste celular.',
                  ),
                ),
                // Na escola a chave vem dela: PIN de backup só no modo isolado.
                if (!pairing.workspaceAtivo) ...[
                  if (!pairing.backupAtivo)
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Ativar backup'),
                      subtitle: const Text('Cria um PIN para abrir o backup em outro celular.'),
                      onTap: () async {
                        final pin = await _pedirPin(
                          titulo: 'Criar PIN de backup',
                          acao: 'Ativar backup',
                        );
                        if (pin == null || !mounted) return;
                        await pairing.ativarBackup(pin);
                        if (mounted) {
                          _snack('Backup ativado.');
                          setState(() {});
                        }
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Restaurar backup neste celular'),
                    subtitle: const Text('Traz os dados de outro aparelho (pede o PIN).'),
                    onTap: _restaurar,
                  ),
                ],
              ],
            ],
          ),
          GrupoDeOpcoes(
            titulo: 'Preferências',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aparência', style: Theme.of(context).listTileTheme.titleTextStyle),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
                          ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
                        ],
                        selected: {widget.settings.themeMode},
                        onSelectionChanged: (sel) => widget.settings.setThemeMode(sel.first),
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Avisar com som'),
                subtitle: const Text(
                  'Quando um computador abrir um site marcado "Só me avisar" ou '
                  'tentar um site bloqueado.',
                ),
                value: widget.settings.notificarSites,
                onChanged: (v) => widget.settings.setNotificarSites(v),
              ),
              if (_notificacoesBloqueadas)
                ListTile(
                  leading: Icon(
                    Icons.notifications_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Notificações bloqueadas pelo sistema'),
                  subtitle: const Text(
                    'Libere nas configurações do Android para ouvir os avisos.',
                  ),
                ),
            ],
          ),
          const GrupoDeOpcoes(
            titulo: 'Sobre',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Controle de Aula'),
                subtitle: Text('Versão $kVersaoApp'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
