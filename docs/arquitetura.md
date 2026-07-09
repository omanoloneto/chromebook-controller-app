# Arquitetura — App (celular do professor)

## Visão geral

Transporte via **Firebase Realtime Database** (projeto `controle-de-aula-f53bd`),
com criptografia **ponta-a-ponta** por cima — o banco só carrega envelopes
cifrados. Celular e Chromebooks podem estar em **redes diferentes**.

- **App (este repo)** = cliente RTDB autenticado com **Auth anônima** (o uid é
  a identidade do professor nas Security Rules).
- **Extensões (Chromebooks)** = clientes RTDB; cada PC tem seu nó
  `/devices/{deviceId}` e é pareado **1x por QR**.

```
   APP (professor)                RTDB                 CHROMEBOOKS
   escaneia QR ──► grava bind ───► ◄──────────────── exibem QR {id,pub,tok}
   cmd/{push} (envelope) ────────► ◄── stream SSE ── executam, ack, deletam
   state/rules|wallpaper ────────► ◄── stream SSE ── aplicam (persiste offline)
   ◄──── report (envelope) ────── ◄───────────────── PUT a cada mudança/60s
   ◄──── presence.lastSeen ────── ◄───────────────── heartbeat 25s
```

## Camadas (Flutter)

| Camada | Caminho | Responsabilidade |
|--------|---------|------------------|
| **Transporte** | `lib/src/cloud/firebase_transport.dart` | Listener do roster + listeners por PC (report/presence/ack/bind/label); sela comandos `{sid,seq,ts}` p/ `cmd/` e `state/`; `pairDevice` (QR), `forgetDevice`, `publishWallpaper`. |
| **Sessões** | `lib/src/cloud/session_registry.dart` | Mapa de PCs (chave de sessão, guards anti-replay, **abas/histórico por PC**, presença). |
| **Anti-replay** | `lib/src/cloud/replay_guard.dart` | Épocas `sid`/`seq` (paridade com `replay.js`; teste `test/replay_test.dart`). |
| **QR** | `lib/src/cloud/qr_payload.dart` | Parse/validação do QR de pareamento (v4). |
| **Cripto** | `lib/src/secure/` | `crypto.dart` (AES-256-GCM), `keypair.dart` (X25519+HKDF), `key_store.dart` (persiste o par do professor). **Inalterados do v3.** |
| **Controle** | `lib/src/pairing/` | `pairing_controller.dart` (auth anônima; liga o transporte; expõe PCs, comandos, nomes, regras, favoritos, wallpaper, `parearComQr`, `esquecerPc`), `name_store.dart`, `rules_store.dart`, `favorites_store.dart`. |
| **Serviço** | `lib/src/service/foreground_service.dart` | Foreground service (`connectedDevice`): listeners RTDB vivos com a tela apagada; handler no-op. |
| **UI** | `lib/src/ui/` | `home_page.dart` (URL + favoritos + turma + cartões com alerta + botão de scan), `scan_page.dart` (câmera, pareia vários em sequência), `device_page.dart` (abas, histórico, renomear, esquecer), `rules_page.dart`, `favorites_page.dart`. |
| **Firebase** | `lib/firebase_options.dart` | Config do projeto (init via Dart, sem google-services.json). `firebase/` tem as **Security Rules** (canônicas) + emuladores. |

## Pareamento (QR + TOFU no servidor)

- O QR do Chromebook carrega `{deviceId, devicePub, token}`. Ao escanear, o app
  deriva a chave de sessão (X25519+HKDF — paridade `keypair_test.dart`) e grava
  o `bind`; as **rules validam o token** (uso único) e impõem **TOFU** (`bind`
  existente não pode ser sobrescrito por outro professor).
- O par de chaves X25519 do professor é **persistido** (`key_store.dart`) — se
  mudasse a cada execução, os PCs pareados rejeitariam o app.
- Estado vigente (`state/rules`, `state/wallpaper`) é gravado no pareamento e
  **persiste no banco** — PC que conecta atrasado lê ao conectar (substitui o
  antigo "reenviar a cada bind").

## Presença e ciclo de vida

- Presença = heartbeat do PC (25s, timestamp do servidor); o app considera
  **online < 60s**, corrigindo o relógio com `.info/serverTimeOffset`.
- **Foreground service** (`connectedDevice`): conexão RTDB viva com a tela
  apagada; notificação mostra "N PC(s) conectados". Sem a permissão de
  notificação o serviço roda igual.

## Pontos de atenção

- **Console Firebase:** Auth anônima ON; rules publicadas
  (`firebase/database.rules.json`). Auth padrão não apaga contas anônimas;
  com upgrade p/ Identity Platform, manter "Automatic clean-up" OFF.
- **Reinstalar o app** perde a identidade (chave + uid) → cada PC precisa
  desvincular (popup) e re-parear.
- **Privacidade:** abas/histórico ficam **só na memória** do app (zeram ao
  fechar); o ciphertext do último report repousa no banco (E2E — só a chave do
  professor abre; o PC apaga ao desvincular). Persistidos no celular: nomes dos
  PCs, regras e favoritos. O blob do wallpaper fica **em claro** no banco
  (risco aceito — ver protocolo).
- **Banda (Spark 10GB/mês):** presença+reports = dezenas de MB/dia por turma;
  wallpaper ≈ 80MB por troca (30 PCs). Várias turmas → considerar Blaze.
