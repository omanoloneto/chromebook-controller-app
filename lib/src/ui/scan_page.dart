// Scanner de QR de pareamento — fica aberto para parear vários Chromebooks
// em sequência (um QR por PC). Ver docs/protocolo.md §2.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../pairing/pairing_controller.dart';
import 'theme.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  // Debounce: a câmera lê o mesmo QR várias vezes por segundo.
  String? _ultimoRaw;
  DateTime _ultimoEm = DateTime.fromMillisecondsSinceEpoch(0);
  bool _processando = false;
  int _pareados = 0;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processando) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final agora = DateTime.now();
    if (raw == _ultimoRaw && agora.difference(_ultimoEm) < const Duration(seconds: 4)) {
      return; // mesmo QR ainda na frente da câmera
    }
    _ultimoRaw = raw;
    _ultimoEm = agora;

    _processando = true;
    final erro = await widget.pairing.parearComQr(raw);
    _processando = false;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = cores(context);
    messenger.hideCurrentSnackBar();
    if (erro == null) {
      setState(() => _pareados++);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ PC pareado! Pode escanear o próximo.',
            style: TextStyle(color: c.onOnline),
          ),
          backgroundColor: c.online,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(erro, style: TextStyle(color: scheme.onError)),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pareados == 0
              ? 'Conectar um Chromebook'
              : 'Pareados nesta sessão: $_pareados',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Lanterna',
            onPressed: () => _scanner.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            // black54/white de propósito: o overlay fica sobre o feed da
            // câmera (sempre "escuro"), independe do tema claro/escuro.
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Aponte para o QR no popup da extensão (ou na página '
                '"QR em tela cheia") de cada Chromebook.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
