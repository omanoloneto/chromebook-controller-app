// Tela inicial do controle.
// Esboço: layout provisório. A lógica (pareamento, envio de URL) será ligada
// aos controladores em src/pairing/ e src/webrtc/.

import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controle de Aula')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TODO: indicador de status da conexão (não pareado/conectado).
            Text('Status: não pareado'),
            SizedBox(height: 24),

            // TODO: campo para digitar a URL a enviar ao Chromebook.
            TextField(
              decoration: InputDecoration(
                labelText: 'Endereço do site',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),

            // TODO: botão "Abrir no Chromebook" -> envia comando open_url.
          ],
        ),
      ),
      floatingActionButton: const FloatingActionButton.extended(
        // TODO: iniciar o pareamento (abrir câmera para ler o QR #1).
        onPressed: null,
        icon: Icon(Icons.qr_code_scanner),
        label: Text('Parear'),
      ),
    );
  }
}
