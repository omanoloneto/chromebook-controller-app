// Cliente WebRTC do app (papel "answerer"). Ver docs/protocolo.md.
//
// Recebe o OFFER (lido do QR #1), gera o ANSWER (vira o QR #2) e, quando o
// DataChannel abre, fica conectado ao Chromebook.

import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Estados expostos para a UI.
enum ConnState { idle, connecting, connected, disconnected }

class WebrtcAnswerer {
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;

  // Sem servidor: iceServers vazio => só host candidates (LAN).
  static const Map<String, dynamic> _config = {'iceServers': <dynamic>[]};
  static const Duration _iceTimeout = Duration(seconds: 3);

  void Function(ConnState state)? onState;
  void Function(String raw)? onMessage;

  /// Recebe o SDP do offer e devolve o SDP do answer (já com os candidatos ICE).
  Future<String> answerFromOffer(String offerSdp) async {
    await close();
    onState?.call(ConnState.connecting);

    final pc = await createPeerConnection(_config);
    _pc = pc;

    pc.onDataChannel = _wireChannel;
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onState?.call(ConnState.disconnected);
      }
    };

    final iceDone = _armIceComplete(pc);

    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    await iceDone;

    final local = await pc.getLocalDescription();
    final sdp = local?.sdp;
    if (sdp == null) {
      throw StateError('answer_sem_sdp');
    }
    return sdp;
  }

  // Completa quando o ICE gathering termina (ou estoura o timeout) — non-trickle.
  Future<void> _armIceComplete(RTCPeerConnection pc) {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      finish();
    }
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) finish();
    };
    pc.onIceCandidate = (candidate) {
      // candidato nulo/vazio marca o fim do gathering em algumas plataformas.
      if (candidate.candidate == null || candidate.candidate!.isEmpty) finish();
    };
    Future<void>.delayed(_iceTimeout, finish);
    return completer.future;
  }

  void _wireChannel(RTCDataChannel channel) {
    _channel = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        onState?.call(ConnState.connected);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        onState?.call(ConnState.disconnected);
      }
    };
    channel.onMessage = (msg) => onMessage?.call(msg.text);
  }

  /// Envia uma mensagem do protocolo (JSON em uma linha) pelo DataChannel.
  Future<void> send(String message) async {
    final ch = _channel;
    if (ch == null) throw StateError('sem_canal');
    await ch.send(RTCDataChannelMessage(message));
  }

  bool get isConnected =>
      _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> close() async {
    try {
      await _channel?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _channel = null;
    _pc = null;
  }
}
