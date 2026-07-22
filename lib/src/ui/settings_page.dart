// Aba Ajustes: aparência (tema), nome do professor, papel de parede e versão.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../pairing/pairing_controller.dart';
import 'settings_controller.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.pairing, required this.settings});

  final PairingController pairing;
  final SettingsController settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onChange);
    widget.pairing.addListener(_onChange);
  }

  @override
  void dispose() {
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

  Future<void> _escolherPapelDeParede() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (img == null || !mounted) return;
    final n = widget.pairing.pcs.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Papel de parede'),
        content: Text('Aplicar esta imagem como papel de parede em $n PC(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.pairing.definirPapelDeParede(await img.readAsBytes());
    _snack('Papel de parede enviado para $n PC(s). (Só funciona em ChromeOS.)');
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
    _snack('Criando o workspace da escola…');
    final erro = await widget.pairing.criarWorkspace();
    if (!mounted) return;
    _snack(erro ?? 'Workspace criado — seus PCs e dados agora são da escola.');
    setState(() {});
  }

  Future<void> _entrarWorkspace() async {
    // A chave local é sobrescrita pela da escola: PCs pareados com a chave
    // própria deixam de responder (precisam re-parear).
    if (widget.pairing.pcs.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Entrar no workspace da escola'),
          content: Text(
            'Este celular tem ${widget.pairing.pcs.length} PC(s) pareado(s) '
            'com a sua chave pessoal. Ao entrar, eles vão precisar re-parear '
            '(desvincular no popup e escanear o QR de novo). Continuar?',
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
    _snack('Entrando no workspace…');
    final erro = await widget.pairing.entrarNoWorkspace();
    if (!mounted) return;
    _snack(erro ?? 'Você entrou no workspace da escola.');
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
      _snack('Não deu para entrar: ${r.substring(5)}');
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
            '(PCs pareados, histórico, turmas).',
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

  Widget _secao(String titulo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          _secao('Aparência'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistema'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Claro'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Escuro'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {widget.settings.themeMode},
              onSelectionChanged: (sel) =>
                  widget.settings.setThemeMode(sel.first),
            ),
          ),
          _secao('Workspace da escola'),
          if (widget.pairing.workspaceAtivo)
            const ListTile(
              leading: Icon(Icons.school_outlined),
              title: Text('Workspace ativo'),
              subtitle: Text(
                'PCs, turmas, regras e histórico compartilhados entre os '
                'professores da escola.',
              ),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Entrar no workspace da escola'),
              subtitle: const Text(
                'Login Google — você passa a ver os PCs e turmas da escola.',
              ),
              onTap: _entrarWorkspace,
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Criar o workspace (fundador)'),
              subtitle: const Text(
                'Uma vez só, pelo primeiro professor: seus PCs e dados viram '
                'os da escola.',
              ),
              onTap: _criarWorkspace,
            ),
          ],
          _secao('Conta (backup e troca de celular)'),
          if (!widget.pairing.logadoComGoogle)
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Entrar com o Google'),
              subtitle: const Text(
                'Guarda seus dados na nuvem para trocar de celular depois.',
              ),
              onTap: _entrarComGoogle,
            )
          else ...[
            ListTile(
              leading: Icon(
                widget.pairing.backupAtivo
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
              title: Text('Conectado: ${widget.pairing.emailGoogle ?? 'Google'}'),
              subtitle: Text(
                widget.pairing.workspaceAtivo
                    ? 'Favoritos e preferências sincronizados na nuvem.'
                    : widget.pairing.backupAtivo
                        ? 'Backup ativo — dados sincronizados na nuvem.'
                        : 'Backup ainda não ativado neste celular.',
              ),
            ),
            // No workspace a chave vem da escola — PIN de backup só faz
            // sentido no modo isolado.
            if (!widget.pairing.workspaceAtivo) ...[
              if (!widget.pairing.backupAtivo)
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Ativar backup (criar PIN)'),
                  onTap: () async {
                    final pin = await _pedirPin(
                      titulo: 'Criar PIN de backup',
                      acao: 'Ativar backup',
                    );
                    if (pin == null || !mounted) return;
                    await widget.pairing.ativarBackup(pin);
                    if (mounted) {
                      _snack('Backup ativado.');
                      setState(() {});
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restaurar backup neste celular'),
                subtitle:
                    const Text('Traz os dados de outro aparelho (pede o PIN).'),
                onTap: _restaurar,
              ),
            ],
          ],
          _secao('Professor'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Nome do professor'),
            subtitle: Text(widget.settings.nomeProfessor),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editarNome,
          ),
          _secao('Notificações'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Avisar com som'),
            subtitle: const Text(
              'Quando um PC abrir site de alerta ou tentar um site bloqueado.',
            ),
            value: widget.settings.notificarSites,
            onChanged: (v) => widget.settings.setNotificarSites(v),
          ),
          FutureBuilder<bool?>(
            future: widget.pairing.notificacoes?.habilitadasNoSistema(),
            builder: (_, snap) => snap.data == false
                ? ListTile(
                    leading: Icon(
                      Icons.notifications_off_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Notificações bloqueadas pelo sistema'),
                    subtitle: const Text(
                      'Libere nas configurações do Android para ouvir os avisos.',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          _secao('Turma'),
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Papel de parede da turma'),
            subtitle: const Text('Aplicar uma imagem em todos os PCs (ChromeOS)'),
            onTap: _escolherPapelDeParede,
          ),
          _secao('Sobre'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Versão'),
            subtitle: Text(kVersaoApp),
          ),
        ],
      ),
    );
  }
}
