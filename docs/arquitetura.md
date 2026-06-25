# Arquitetura — App (celular, servidor)

## Visão geral

O **Controle de Aula** funciona na **rede local**, sem nuvem. Os papéis são:

- **Celular (este app) = servidor HTTP** local. Abre uma porta na LAN e mostra
  **1 QR** com `{ip, porta, chave}`. Origina os comandos (ex.: `open_url`).
- **Extensão (Chromebook) = cliente.** Lê o QR, conecta e faz **long-poll**
  buscando comandos.

```
        REDE LOCAL DA ESCOLA (mesma Wi-Fi)
┌────────────────────────────────────────────────────────┐
│   CELULAR (este app, servidor)    CHROMEBOOK (extensão)  │
│   HttpServer.bind(:porta)         long-poll cliente      │
│   mostra QR  ── câmera ─────────► lê o QR                 │
│   professor digita URL                                   │
│   open_url ─ cifrado (AES-GCM) ─► abre a aba             │
│            ◄──── ACK cifrado ────                         │
└────────────────────────────────────────────────────────┘
```

> **Por que o celular é o servidor?** A extensão Chrome MV3 **não pode abrir
> porta**; ela só faz conexões de saída. Então quem escuta é o celular.

## Camadas do app (Flutter)

| Camada | Caminho | Responsabilidade |
|--------|---------|------------------|
| **Servidor** | `lib/src/server/control_server.dart` | `HttpServer.bind` na LAN. Rotas `GET /`, `POST /poll` (long-poll ~25s), `POST /ack`. Fila de comandos, `seq`, estado de conexão. |
| **Rede** | `lib/src/server/lan.dart` | Descobre o IP do celular na LAN (`NetworkInterface`, faixas privadas, prefere Wi-Fi). |
| **Cripto** | `lib/src/secure/crypto.dart` | AES-256-GCM. `seal/open` no formato `nonce\|\|ct\|\|tag`. Gera a chave de 32 bytes. Espelha o `crypto.js` da extensão. |
| **Pareamento** | `lib/src/pairing/` | `pairing_payload.dart` monta o QR; `pairing_controller.dart` orquestra o servidor e expõe `sendOpenUrl`. |
| **Comandos** | `lib/src/commands/command.dart` | Monta `open_url` (em claro; a cifragem é feita pelo servidor) e parseia o `Ack`. |
| **UI** | `lib/src/ui/home_page.dart` | Mostra o QR, o status e, conectado, o campo de URL. |

## Segurança

A chave de 256 bits é gerada por sessão e vai **só no QR** (canal físico via
câmera). Todo comando/ACK é AES-256-GCM com `seq` (anti-replay) e janela de `ts`.
Detalhes em [`protocolo.md`](protocolo.md). Há **teste de paridade** da cripto com
o lado JS (`test/crypto_test.dart`) garantindo o mesmo formato no fio.

## Ciclo de vida do servidor (escopo)

- **MVP: foreground.** O servidor roda enquanto o app está aberto (o professor
  segura o celular). Sem `INTERNET` extra além do necessário para abrir o socket.
- **Fase 2:** *foreground service* (notificação persistente) para o servidor
  sobreviver com a tela apagada — exige `FOREGROUND_SERVICE`/`POST_NOTIFICATIONS`.

## Pontos de atenção

- **Rede da escola:** *client/AP isolation* bloqueia qualquer conexão LAN.
- **IP do celular muda** (DHCP / troca de rede) → o QR antigo expira; reparear.
- **Permissões Android:** `INTERNET` (abrir socket) e `ACCESS_NETWORK_STATE`
  (detectar Wi-Fi). **Sem** câmera (o app só mostra o QR).
