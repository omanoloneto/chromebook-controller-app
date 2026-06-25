// Tela inicial do controle: parear (ler QR #1 -> mostrar QR #2) e, conectado,
// enviar uma URL para o Chromebook.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import '../webrtc/webrtc_client.dart';

enum _Step { inicio, lendoQr, mostrandoQr, conectado }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PairingController _pairing = PairingController();
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://');

  _Step _step = _Step.inicio;
  String? _answerPayload;
  bool _tratandoLeitura = false;
  MobileScannerController? _scanner;

  @override
  void initState() {
    super.initState();
    _pairing.onState = _aoMudarEstado;
    _pairing.onMessage = _aoReceberMensagem;
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _pairing.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _aoMudarEstado(ConnState state) {
    if (!mounted) return;
    setState(() {
      if (state == ConnState.connected) {
        _step = _Step.conectado;
      } else if (state == ConnState.disconnected &&
          _step == _Step.conectado) {
        _step = _Step.inicio;
      }
    });
  }

  void _aoReceberMensagem(String raw) {
    final ack = Ack.tryParse(raw);
    if (ack != null && mounted) {
      _snack(ack.ok ? 'Aberto no Chromebook ✅' : 'Erro: ${ack.error}');
    }
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  void _iniciarLeitura() {
    _scanner?.dispose();
    _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    setState(() {
      _tratandoLeitura = false;
      _step = _Step.lendoQr;
    });
  }

  Future<void> _aoDetectar(BarcodeCapture cap) async {
    if (_tratandoLeitura) return;
    final code = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (code == null || code.isEmpty) return;
    _tratandoLeitura = true;
    await _scanner?.stop();

    try {
      final answer = await _pairing.handleScannedOffer(code);
      if (!mounted) return;
      setState(() {
        _answerPayload = answer;
        _step = _Step.mostrandoQr;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('QR inválido ($e). Tente novamente.');
      _tratandoLeitura = false;
      await _scanner?.start();
    }
  }

  Future<void> _enviarUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    try {
      await _pairing.sendOpenUrl(url);
    } catch (e) {
      _snack('Falha ao enviar: $e');
    }
  }

  Future<void> _desconectar() async {
    await _pairing.dispose();
    _scanner?.dispose();
    _scanner = null;
    if (mounted) setState(() => _step = _Step.inicio);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Aula'),
        actions: [
          if (_step == _Step.conectado)
            IconButton(
              onPressed: _desconectar,
              icon: const Icon(Icons.link_off),
              tooltip: 'Desconectar',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (_step) {
          _Step.inicio => _inicio(),
          _Step.lendoQr => _lendoQr(),
          _Step.mostrandoQr => _mostrandoQr(),
          _Step.conectado => _conectado(),
        },
      ),
    );
  }

  Widget _inicio() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cast, size: 72, color: Color(0xFF2962FF)),
        const SizedBox(height: 16),
        const Text(
          'Conecte-se ao Chromebook do professor para enviar sites para a tela.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _iniciarLeitura,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Parear'),
        ),
      ],
    );
  }

  Widget _lendoQr() {
    return Column(
      children: [
        const Text(
          '1. Aponte para o QR mostrado na extensão do Chromebook.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _scanner,
              onDetect: _aoDetectar,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mostrandoQr() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '2. Mostre este QR para a câmera do Chromebook.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: QrImageView(
            data: _answerPayload ?? '',
            version: QrVersions.auto,
            size: 260,
            errorStateBuilder: (context, error) => const SizedBox(
              width: 260,
              height: 260,
              child: Center(child: Text('Não foi possível gerar o QR.')),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Aguardando o Chromebook conectar…'),
        const SizedBox(height: 8),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }

  Widget _conectado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF00897B)),
            SizedBox(width: 8),
            Text('Conectado ao Chromebook'),
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
