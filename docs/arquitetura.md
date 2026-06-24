# Arquitetura — App de controle (celular)

## Visão geral

O **Controle de Aula** tem dois componentes que conversam **diretamente pela
rede local**, sem nenhum servidor central:

- **App de controle** (este repo, no celular Android) — envia comandos.
- **Extensão** (no Chromebook do professor) — recebe comandos e age no navegador.

```
        REDE LOCAL DA ESCOLA (mesma Wi-Fi)
┌──────────────────────────────────────────────────────┐
│                                                        │
│   ┌───────────────┐                ┌────────────────┐  │
│   │   Celular     │  WebRTC P2P    │   Chromebook   │  │
│   │   (este app)  │ ─────────────► │   (extensão)   │  │
│   │               │   DataChannel  │                │  │
│   │  - escolhe    │ ◄───────────── │  - abre aba    │  │
│   │    a URL      │      ACK       │  - dá foco     │  │
│   └───────────────┘                └────────────────┘  │
│                                                        │
└──────────────────────────────────────────────────────┘
```

## Papel do app no WebRTC

No handshake, o app é o **answerer** (responde ao convite da extensão):

1. Escaneia o **QR #1** mostrado pela extensão (contém o *offer*).
2. Cria o *answer* e mostra o **QR #2** para o Chromebook ler.
3. Quando o `RTCDataChannel` abre, está conectado.

Detalhes em [`protocolo.md`](protocolo.md).

## Camadas do app (Flutter)

| Camada | Pasta | Responsabilidade |
|--------|-------|------------------|
| **UI** | `lib/src/ui/` | Telas: pareamento, tela inicial com campo de URL e atalhos, status. |
| **Pareamento** | `lib/src/pairing/` | Ler o QR #1 (câmera) e gerar o QR #2 (answer). |
| **WebRTC** | `lib/src/webrtc/` | Cliente `flutter_webrtc` no papel *answerer*; envia comandos e recebe ACKs. |
| **Comandos** | `lib/src/commands/` | Modelos das mensagens do protocolo (serialização JSON). |

## Pacotes previstos

- `flutter_webrtc` — conexão WebRTC / DataChannel.
- `mobile_scanner` — leitura do QR #1 pela câmera.
- `qr_flutter` — geração do QR #2 (answer).

## Pontos de atenção

- **Rede da escola:** algumas redes isolam dispositivos (*client isolation*),
  bloqueando a conexão direta. Documentar isso para o professor/TI.
- **Reconexão:** guardar o último pareamento para reconectar sem refazer os QR.
- **Permissão de câmera:** necessária para o `mobile_scanner`.
- **Sem STUN/TURN:** em rede local, *host candidates* normalmente bastam.

## Decisões em aberto

- Lista de atalhos de sites favoritos do professor.
- Controlar vários Chromebooks (turma) a partir de um celular.
- PIN/confirmação além do QR para evitar pareamento indevido.
