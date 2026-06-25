// Tela inicial: lista os PCs (Chromebooks) que se vincularam a este celular e
// permite abrir um site na turma toda ou num PC específico.

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';

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
    if (widget.autoStart) _iniciar();
  }

  Future<void> _iniciar() async {
    _pairing.onChange = () {
      if (mounted) setState(() {});
    };
    try {
      await _pairing.start();
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erro = _pairing.ip == null
              ? 'Sem Wi-Fi detectado. Conecte o celular à rede da escola.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _iniciando = false;
          _erro = 'Não foi possível iniciar o servidor: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pairing.stop();
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

  @override
  Widget build(BuildContext context) {
    final pcs = _pairing.pcs;
    final online = pcs.where(_pairing.isOnline).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Aula'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('$online online')),
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
            const Icon(Icons.wifi_off, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_erro!, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _conteudo(List pcs) {
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
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _abrirEmTodos,
                icon: const Icon(Icons.groups),
                label: const Text('Abrir na turma toda'),
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
              'Procurando PCs na rede…\nAbra um Chromebook com a extensão instalada na mesma Wi-Fi.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Este celular: ${_pairing.ip}:${_pairing.port}',
              style: const TextStyle(fontFamily: 'monospace', color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pcTile(dynamic s) {
    final on = _pairing.isOnline(s);
    return ListTile(
      leading: Icon(
        Icons.computer,
        color: on ? const Color(0xFF00897B) : Colors.grey,
      ),
      title: Text(s.label as String),
      subtitle: Text(on ? 'online' : 'offline'),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Abrir só neste',
        onPressed: on ? () => _abrirEm(s.deviceId as String, s.label as String) : null,
      ),
    );
  }
}
