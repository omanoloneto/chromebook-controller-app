# Controle de Aula — App (controle no celular)

App **Flutter** (Android) que vira um **servidor local** na rede da escola e
controla o Chromebook do professor. Faz parte do projeto **Controle de Aula**:

| Componente | Repositório | Papel |
|------------|-------------|-------|
| **App de controle** (este repo) | `chromebook-controller-app` | **Servidor** no celular Android |
| **Extensão** | [`chromebook-controller-extension`](https://github.com/omanoloneto/chromebook-controller-extension) | **Cliente** no Chromebook |

> ⚠️ **Status:** em desenvolvimento. Pareamento e comando **abrir URL** já
> implementados. Não testado ainda entre dois aparelhos reais.

## Como funciona

- O **app roda um servidor HTTP** local e mostra **1 QR** (`ip`, `porta`, `chave`).
- A **extensão (Chromebook) é cliente**: lê o QR e faz **long-poll** buscando
  comandos.
- O professor digita uma URL no app → ela abre no Chromebook.
- Tudo **criptografado ponta-a-ponta** (AES-256-GCM); a chave vai **só no QR**.
- **Sem nuvem.** Direto na LAN.

```
CELULAR (este app, servidor)               CHROMEBOOK (extensão, cliente)
abre porta + mostra QR  ── câmera ──────►  lê o QR
professor digita URL                                    
open_url (cifrado) ─────────────────────►  abre a aba
                   ◄──────── ACK cifrado    confirma
```

> **Por que o celular é o servidor?** A extensão MV3 **não pode abrir porta**; só
> faz conexões de saída. Detalhes em [`docs/arquitetura.md`](docs/arquitetura.md)
> e [`docs/protocolo.md`](docs/protocolo.md).

## Estrutura do repositório

```
chromebook-controller-app/
├── lib/
│   ├── main.dart
│   └── src/
│       ├── server/          # control_server.dart (HttpServer), lan.dart (IP)
│       ├── secure/         # crypto.dart (AES-256-GCM)
│       ├── pairing/       # pairing_payload.dart (QR), pairing_controller.dart
│       ├── commands/     # command.dart (open_url, Ack)
│       └── ui/          # home_page.dart (mostra QR, dispara comandos)
├── test/              # crypto_test.dart (paridade com o JS) + smoke test
├── android/          # projeto Android (org: pro.omanoloneto)
├── docs/            # arquitetura, protocolo, instalação
└── pubspec.yaml
```

## Tecnologias

- **Flutter / Dart**, `dart:io HttpServer` (servidor local)
- [`cryptography`](https://pub.dev/packages/cryptography) — AES-256-GCM
- [`qr_flutter`](https://pub.dev/packages/qr_flutter) — gera o QR de pareamento

## Rodando

`flutter pub get` e `flutter run` (Android). Plataforma já incluída
(`applicationId pro.omanoloneto.controle_de_aula`). Uso em
[`docs/instalacao.md`](docs/instalacao.md).

## Roteiro

- [x] Servidor local + **1 QR** de pareamento
- [x] Transporte cifrado (AES-256-GCM) com anti-replay
- [x] Comando **abrir URL** + status de conexão
- [ ] *Foreground service* (servir com a tela apagada)
- [ ] Atalhos de sites favoritos
- [ ] Comandos futuros: bloquear/liberar tela, mensagem, fechar abas

## Contribuindo

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Documentação em português.

## Licença

[MIT](LICENSE) © 2026 Mano Afonso (@omanoloneto)
