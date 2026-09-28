// Relógio do servidor visto pelo celular: offset de .info/serverTimeOffset.
// Antes do primeiro valor real o offset é 0 (vale o relógio do celular).

import 'dart:async';

class RelogioDoServidor {
  int offsetMs = 0;
  bool _conectado = false;
  bool _offsetRecebido = false;
  final Completer<void> _pronto = Completer<void>();

  /// Conclui quando o offset veio do servidor com a conexão de pé. Quem apaga
  /// por data (poda) espera isto: o relógio do celular pode estar errado.
  Future<void> get pronto => _pronto.future;

  void aoReceberOffset(Object? valor) {
    if (valor is! num) return; // nó vazio = ainda sem handshake
    offsetMs = valor.toInt();
    _offsetRecebido = true;
    _avaliar();
  }

  void aoMudarConexao(Object? valor) {
    _conectado = valor == true;
    _avaliar();
  }

  void _avaliar() {
    if (_conectado && _offsetRecebido && !_pronto.isCompleted) {
      _pronto.complete();
    }
  }

  DateTime agora() => DateTime.now().add(Duration(milliseconds: offsetMs));
}
