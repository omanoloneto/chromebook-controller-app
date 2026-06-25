// Tela inicial: o celular vira servidor, mostra 1 QR e dispara comandos.
// O Chromebook escaneia o QR e conecta. Sem botão de cancelar.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../pairing/pairing_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.autoStart = true});

  /// Em testes, passe false para não iniciar o servidor/timers.
  final bool autoStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PairingController _pairing = PairingController();
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://');

  bool _iniciando = true;
  bool _conectado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _iniciar();
  }

  Future<void> _iniciar() async {
    _pairing.onConnection = (c) {
      if (mounted) setState(() => _conectado = c);
    };
    _pairing.onAck = (ack) {
      if (mounted) {
        _snack(ack.ok ? 'Aberto no Chromebook ✅' : 'Erro: ${ack.error}');
      }
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
          _erro = 'Não foi possível iniciar: $e';
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

  void _enviarUrl() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    _pairing.sendOpenUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Aula'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _conectado ? 'Conectado' : 'Aguardando',
                style: TextStyle(
                  color: _conectado ? const Color(0xFF00E676) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _iniciando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? _erroView()
                : _conectado
                    ? _controleView()
                    : _qrView(),
      ),
    );
  }

  Widget _erroView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(_erro!, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _qrView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            'Escaneie este código com a câmera da extensão no Chromebook.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: _pairing.qrPayload ?? '',
              version: QrVersions.auto,
              size: 260,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${_pairing.ip}:${_pairing.port}',
            style: const TextStyle(fontFamily: 'monospace', color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mantenha este app aberto. A conexão é direta e criptografada.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _controleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF00897B)),
            SizedBox(width: 8),
            Expanded(child: Text('Conectado ao Chromebook')),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Endereço do site',
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _enviarUrl(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _enviarUrl,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir no Chromebook'),
        ),
      ],
    );
  }
}
