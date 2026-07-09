// Tela inicial: lista os PCs (Chromebooks) que se vincularam a este celular e
// permite abrir um site na turma toda ou num PC específico.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../cloud/session_registry.dart';
import '../pairing/pairing_controller.dart';
import 'device_page.dart';
import 'favorites_page.dart';
import 'rules_page.dart';
import 'scan_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.autoStart = true});

  /// Em testes, passe false para não iniciar o servidor.
  final bool autoStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PairingController _pairing = PairingController();
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://');

  bool _iniciando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onPairingChange);
    if (widget.autoStart) _iniciar();
  }

  void _onPairingChange() {
    if (mounted) setState(() {});
  }

  Future<void> _iniciar() async {
    try {
      await _pairing.start();
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erro = null;
        });
      }
    } catch (e) {
      // Só erros de config/auth chegam aqui; queda de rede transitória o
      // FlutterFire reconecta sozinho.
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erro = 'Não foi possível conectar ao Firebase: $e\n'
              'Verifique a internet do celular.';
        });
      }
    }
  }

  Future<void> _abrirScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanPage(pairing: _pairing)),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pairing.removeListener(_onPairingChange);
    _pairing.stop();
    _pairing.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  void _abrirEmTodos() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final n = _pairing.pcs.length;
    if (n == 0) {
      _snack('Nenhum PC conectado ainda.');
      return;
    }
    _pairing.abrirEmTodos(url);
    _snack('Enviado para $n PC(s).');
  }

  void _abrirEm(String deviceId, String label) {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    _pairing.abrirEm(deviceId, url);
    _snack('Enviado para $label.');
  }

  Future<void> _fecharSiteEmTodos() async {
    final dominio = dominioDe(_urlCtrl.text.trim());
    if (dominio.isEmpty || !dominio.contains('.')) {
      _snack('Digite/escolha um site primeiro.');
      return;
    }
    final n = _pairing.pcs.length;
    if (n == 0) {
      _snack('Nenhum PC conectado ainda.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar site na turma'),
        content: Text('Fechar todas as abas de $dominio em $n PC(s)?'),
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
    if (ok == true) {
      _pairing.fecharSiteEmTodos(dominio);
      _snack('Fechando $dominio em $n PC(s).');
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
    final n = _pairing.pcs.length;
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
    await _pairing.definirPapelDeParede(await img.readAsBytes());
    _snack('Papel de parede enviado para $n PC(s). (Só funciona em ChromeOS.)');
  }

  void _menuFavorito(int indice) {
    final f = _pairing.favoritos[indice];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            ListTile(
              leading: const Icon(Icons.star),
              title: const Text('Editar favoritos'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FavoritesPage(pairing: _pairing),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pcs = _pairing.pcs;
    final online = pcs.where(_pairing.isOnline).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Aula'),
        actions: [
          Center(child: Text('$online online')),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Parear PC (escanear QR)',
            onPressed: _abrirScanner,
          ),
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: 'Favoritos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FavoritesPage(pairing: _pairing)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Regras de sites',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RulesPage(pairing: _pairing)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.wallpaper),
            tooltip: 'Papel de parede da turma',
            onPressed: _escolherPapelDeParede,
          ),
        ],
      ),
      body: _iniciando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _erroView()
              : _conteudo(pcs),
    );
  }

  Widget _erroView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_erro!, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _conteudo(List<PcSession> pcs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Endereço do site',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _abrirEmTodos(),
              ),
              if (_pairing.favoritos.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pairing.favoritos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final f = _pairing.favoritos[i];
                      return GestureDetector(
                        onLongPress: () => _menuFavorito(i),
                        child: ActionChip(
                          avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                          label: Text(f.label),
                          onPressed: () => setState(() => _urlCtrl.text = f.url),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _abrirEmTodos,
                icon: const Icon(Icons.groups),
                label: const Text('Abrir na turma toda'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _fecharSiteEmTodos,
                icon: const Icon(Icons.close),
                label: const Text('Fechar este site na turma'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: pcs.isEmpty
              ? _vazio()
              : ListView.separated(
                  itemCount: pcs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _pcTile(pcs[i]),
                ),
        ),
      ],
    );
  }

  Widget _vazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.devices_other, size: 56, color: Colors.grey),
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
            const Text(
              'O pareamento é feito uma única vez por PC; depois disso ele '
              'conecta sozinho, mesmo em outra rede Wi-Fi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pcTile(PcSession s) {
    final on = _pairing.isOnline(s);
    final nome = _pairing.nomeDe(s);
    final ativa = s.abaAtiva;
    final alerta = on ? s.alerta : null;
    final String subtitulo;
    if (!on) {
      subtitulo = 'offline';
    } else if (ativa == null) {
      subtitulo = 'online — sem dados de abas';
    } else {
      final titulo = ativa.title.isEmpty ? '(sem título)' : ativa.title;
      final linha = '$titulo\n${dominioDe(ativa.url)}';
      subtitulo = alerta != null ? '⚠ Alerta: $alerta\n$linha' : linha;
    }
    return ListTile(
      tileColor: alerta != null ? Colors.red.shade50 : null,
      leading: Icon(
        alerta != null ? Icons.warning_amber : Icons.computer,
        color: alerta != null
            ? Colors.red
            : on
                ? const Color(0xFF00897B)
                : Colors.grey,
      ),
      title: Text(nome),
      subtitle: Text(
        subtitulo,
        maxLines: alerta != null ? 3 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: on && ativa != null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DevicePage(
            pairing: _pairing,
            deviceId: s.deviceId,
          ),
        ),
      ),
      onLongPress: () =>
          mostrarDialogoRenomear(context, _pairing, s.deviceId, nome),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Abrir só neste',
        onPressed: on ? () => _abrirEm(s.deviceId, nome) : null,
      ),
    );
  }
}
