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
          _secao('Professor'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Nome do professor'),
            subtitle: Text(widget.settings.nomeProfessor),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editarNome,
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
