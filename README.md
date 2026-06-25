# Controle de Aula — App (controle no celular)

App **Flutter** (Android) que vira um **servidor local** e **reconhece
automaticamente** os Chromebooks da rede que têm a extensão — listando-os para o
professor controlar. Faz parte do projeto **Controle de Aula**:

| Componente | Repositório | Papel |
|------------|-------------|-------|
| **App de controle** (este repo) | `chromebook-controller-app` | **Servidor** no celular Android |
| **Extensão** | [`chromebook-controller-extension`](https://github.com/omanoloneto/chromebook-controller-extension) | **Cliente** no Chromebook |

> ⚠️ **Status:** em desenvolvimento. Servidor multi-cliente, vínculo TOFU e o
> comando **abrir URL** já implementados (handshake/cripto validados em teste).
> Conexão real entre 2 aparelhos ainda não testada em campo.

## Como funciona (sem QR)

- O **app roda um servidor HTTP** local (porta fixa 47615) e publica um **banner**.
- Os **Chromebooks (extensão) se descobrem** sozinhos, **vinculam-se** (TOFU) e
  aparecem na **lista** do app.
- O professor digita uma URL → **"Abrir na turma toda"** ou em um PC específico.
- Tudo **criptografado ponta-a-ponta** (X25519 → AES-256-GCM). Sem nuvem.

```
CELULAR (este app, servidor :47615)     CHROMEBOOKS (extensão, clientes)
GET / -> banner               ◄────     varrem a LAN
POST /bind (X25519)           ◄────     vinculam (TOFU)
open_url (cifrado) ───────────────►     abrem a aba
professor: "abrir em todos" / um PC
```

Detalhes: [`docs/arquitetura.md`](docs/arquitetura.md) e
[`docs/protocolo.md`](docs/protocolo.md).

## Estrutura

```
lib/src/
├── server/    # control_server.dart (HttpServer), session_registry.dart, lan.dart
├── secure/    # crypto.dart (AES-GCM), keypair.dart (X25519+HKDF), key_store.dart
├── pairing/   # pairing_controller.dart (orquestra o servidor)
├── commands/  # command.dart (open_url, Ack)
└── ui/        # home_page.dart (lista de PCs + ação na turma)
test/          # crypto_test + keypair_test (paridade com o JS) + smoke test
```

## Tecnologias

- **Flutter / Dart**, `dart:io HttpServer`
- [`cryptography`](https://pub.dev/packages/cryptography) — AES-256-GCM + X25519/HKDF
- [`path_provider`](https://pub.dev/packages/path_provider) — persiste o par do professor

## Rodando

`flutter pub get` e `flutter run`. Uso em [`docs/instalacao.md`](docs/instalacao.md).

## Roteiro

- [x] Servidor multi-cliente + descoberta automática (banner)
- [x] Vínculo exclusivo (TOFU) X25519 + AES-256-GCM por sessão
- [x] Lista de PCs + **abrir na turma toda** / individual
- [ ] *Foreground service* (servir com a tela apagada)
- [ ] Renomear PCs / favoritos de sites
- [ ] Comandos futuros: bloquear tela, mensagem, fechar abas

## Licença

[MIT](LICENSE) © 2026 Mano Afonso (@omanoloneto)
