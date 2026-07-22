# Controle de Aula — App (controle no celular)

App **Flutter** (Android) do professor: pareia Chromebooks por **QR** e os
controla via **Firebase Realtime Database**, com **criptografia ponta-a-ponta**
— funciona mesmo com os aparelhos em **redes Wi-Fi diferentes**. Faz parte do
projeto **Controle de Aula**:

| Componente | Repositório | Papel |
|------------|-------------|-------|
| **App de controle** (este repo) | `chromebook-controller-app` | Celular do professor |
| **Extensão** | [`chromebook-controller-extension`](https://github.com/omanoloneto/chromebook-controller-extension) | Cliente no Chromebook |

> ⚠️ **Status:** em desenvolvimento. Protocolo v4 (Firebase) implementado nos
> dois lados; conexão real entre 2 aparelhos ainda não testada em campo.

## Como funciona (pareamento por QR)

- Cada Chromebook (extensão) exibe um **QR**; o professor **escaneia com o
  app** (1x por PC). O vínculo é **exclusivo** (TOFU imposto nas Security
  Rules) e o token do QR é de **uso único**.
- Depois disso o PC **conecta sozinho de qualquer rede** — o transporte é o
  RTDB (projeto `controle-de-aula-f53bd`), sem servidor local e sem varredura
  de LAN.
- O professor digita uma URL → **"Abrir na turma toda"** ou em um PC específico.
- Cada PC **informa a aba ativa, as abas abertas e o histórico de navegação**
  (somente URLs/títulos — **sem captura de tela**; dados só na memória do
  celular).
- O professor pode **renomear cada PC** com o nome do aluno (fica no celular).
- Tudo **criptografado ponta-a-ponta** (X25519 → AES-256-GCM): o Firebase só
  carrega envelopes cifrados.

```
APP (professor)                RTDB               CHROMEBOOKS (extensão)
escaneia QR ─► grava bind ───►  ◄───────────────  exibem QR {id, pub, token}
cmd/state (cifrado) ─────────►  ◄── stream SSE ── executam, ack
◄──────── report (cifrado) ──   ◄───────────────  abas + histórico
```

Detalhes: [`docs/arquitetura.md`](docs/arquitetura.md) e
[`docs/protocolo.md`](docs/protocolo.md).

## Estrutura

```
lib/src/
├── cloud/     # firebase_transport.dart, session_registry.dart,
│              # replay_guard.dart (anti-replay), qr_payload.dart
├── secure/    # crypto.dart (AES-GCM), keypair.dart (X25519+HKDF), key_store.dart
├── pairing/   # pairing_controller.dart (orquestra), name/rules/favorites stores
├── commands/  # command.dart (open_url, close_tabs, ...), domain_rules.dart
├── service/   # foreground_service.dart (conexão viva com a tela apagada)
└── ui/        # theme.dart (claro/escuro), app_shell (4 abas), aula_page,
               # students_page, sites_page (favoritos+regras), settings_page,
               # device_page, scan_page (QR)
firebase/      # database.rules.json (Security Rules, canônico) + emuladores
test/          # crypto/keypair/replay/tab_report/rules (paridade com o JS)
```

## Tecnologias

- **Flutter / Dart**, FlutterFire (`firebase_core`, `firebase_auth` anônima,
  `firebase_database`)
- [`cryptography`](https://pub.dev/packages/cryptography) — AES-256-GCM + X25519/HKDF
- [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) — leitura do QR
- [`flutter_foreground_task`](https://pub.dev/packages/flutter_foreground_task)

## Rodando

`flutter pub get` e `flutter run`. Setup do Firebase (console + rules) e uso em
[`docs/instalacao.md`](docs/instalacao.md).

## Roteiro

- [x] Transporte Firebase RTDB (protocolo v4) + Auth anônima
- [x] Pareamento por **QR** (token one-time; TOFU nas Security Rules)
- [x] Lista de PCs + **abrir na turma toda** / individual
- [x] **Monitorar abas** (aba ativa, abas abertas, histórico — sem captura de tela)
- [x] **Renomear PCs** / **esquecer PC**
- [x] **Fechar abas/sites** (na turma toda, num PC ou uma aba específica)
- [x] **Regras de sites**: bloquear (vale nos Chromebooks) ou alertar (cartão vermelho)
- [x] **Favoritos** ilimitados (chips na home, reordenáveis)
- [x] ***Foreground service*** (conexão viva com a tela apagada)
- [x] **Papel de parede** da turma (galeria → Chromebooks; só ChromeOS)
- [x] **Turmas e alunos** (cadastro local) + vínculo aluno↔PC por aula
- [x] **Fechar todas as abas** (turma toda ou um PC)
- [x] **Encerrar aula**: fecha o navegador de todos os PCs e limpa os vínculos
- [x] **Desbloquear site para 1 PC** durante a aula (menu do PC / tela de detalhe)
- [x] **Notificações com som**: site de alerta acessado ou bloqueado tentado
- [x] **PC do professor**: fora dos broadcasts/bloqueios; recebe links do
      histórico dos alunos e os avisos (notificação no Chromebook)
- [x] **Ficha do aluno**: aulas que participou (data) + acessos por aula —
      persistido no Firebase SEMPRE cifrado (só o celular do professor decifra)
- [x] **Cadastrar aluno na vinculação** (botão no menu de vínculo do PC)
- [x] **Em aula = só vinculados**: comandos de turma (abrir/fechar/encerrar) só
      atingem PCs vinculados a aluno; fora de aula, todos
- [x] **Layout estilo Instagram** (flat, hairlines, navbar icon-only) + dark AMOLED
- [x] **Visão da turma no telão**: página na extensão do PC do professor com a
      lista de PCs e a aba ativa de cada um (snapshot agregado pelo app,
      re-cifrado só para o telão; ext ≥ 0.4.3)
- [x] **Número da unidade automático**: cada PC pareado ganha o **menor número
      livre** (1..22 e 98 ocupados → próximo é 23); vai no bind; a extensão
      exibe grande no popup; re-parear mantém o número
- [x] **Editar número da unidade** (menu do PC): número ocupado = os dois PCs
      trocam; viaja por `state/unit` (funciona mesmo com o PC offline na hora)
- [x] **Login Google + backup por PIN**: trocar de celular levando tudo
      (chave cifrada pelo PIN; stores sincronizados)
- [ ] Teste de campo (professor + turma real)
- [ ] Comandos futuros: bloquear tela, mensagem

## Licença

[MIT](LICENSE) © 2026 Mano Afonso (@omanoloneto)
