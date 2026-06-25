# Arquitetura — App (celular, servidor multi-cliente)

## Visão geral

Na rede local, sem nuvem:

- **Celular (este app) = servidor** multi-cliente (`dart:io HttpServer`, porta
  fixa **47615**). Publica um **banner** (`GET /`) com sua chave pública.
- **Extensões (Chromebooks) = clientes** que se **descobrem**, **vinculam** (TOFU)
  e fazem short-poll. O app **lista** os PCs e envia comandos (turma toda / um PC).

```
        REDE LOCAL (mesma Wi-Fi)
┌──────────────────────────────────────────────────────────┐
│  CELULAR (este app, servidor :47615)   CHROMEBOOKS        │
│  GET /  -> banner                ◄────  varrem a LAN       │
│  POST /bind (X25519) -> sessão   ◄────  vinculam (TOFU)    │
│  open_url (cifrado) ────────────────►   abrem a aba        │
│           ◄──── ACK cifrado                               │
│  professor: "abrir em todos" / um PC                       │
└──────────────────────────────────────────────────────────┘
```

## Camadas (Flutter)

| Camada | Caminho | Responsabilidade |
|--------|---------|------------------|
| **Servidor** | `lib/src/server/control_server.dart` | Porta fixa; `GET /` (banner), `POST /bind` (X25519), `POST /poll`/`/ack` por `deviceId`. |
| **Sessões** | `lib/src/server/session_registry.dart` | Mapa de PCs vinculados (chave de sessão, `seq`, fila, last-seen); broadcast. |
| **Rede** | `lib/src/server/lan.dart` | IP do celular na LAN (para o banner e o fallback). |
| **Cripto** | `lib/src/secure/` | `crypto.dart` (AES-256-GCM), `keypair.dart` (X25519+HKDF), `key_store.dart` (persiste o par do professor). |
| **Controle** | `lib/src/pairing/pairing_controller.dart` | Inicia o servidor; expõe a lista de PCs e o envio. |
| **UI** | `lib/src/ui/home_page.dart` | Campo de URL + **"Abrir na turma toda"** + lista de PCs (online/offline) com ação individual. |

## Vínculo (TOFU) e persistência

- O par de chaves X25519 do professor é **persistido** (`key_store.dart`,
  `path_provider`) — se mudasse a cada execução, os PCs vinculados rejeitariam o app.
- Cada PC que faz `/bind` vira uma **sessão** com sua própria chave AES (derivada por
  X25519+HKDF — ver [`protocolo.md`](protocolo.md), com **teste de paridade** em
  `test/keypair_test.dart`).

## Ciclo de vida do servidor (escopo)

- **MVP foreground** (app aberto na mão do professor).
- Fase 2: *foreground service* para servir com a tela apagada.

## Pontos de atenção

- **Rede com client/AP isolation** mata a descoberta (e qualquer LAN).
- **IP muda** (DHCP) → as extensões redescobrem sozinhas.
- **Permissões Android:** `INTERNET` (abrir socket) e `ACCESS_NETWORK_STATE`.
