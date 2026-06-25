# Controle de Aula — App (controle no celular)

App **Flutter** (Android) que funciona como **controle remoto** do Chromebook do
professor. Faz parte do projeto **Controle de Aula**, formado por dois
componentes independentes:

| Componente | Repositório | Onde roda |
|------------|-------------|-----------|
| **App de controle** (este repo) | `chromebook-controller-app` | Celular Android do professor |
| **Extensão** | [`chromebook-controller-extension`](https://github.com/omanoloneto/chromebook-controller-extension) | Chromebook do professor (ligado ao projetor) |

> ⚠️ **Status:** projeto em fase inicial. Este repositório contém a **estrutura,
> a documentação e os esqueletos de código**. As funções ainda **não estão
> implementadas** — veja o [roteiro](#roteiro).

## Para que serve

O professor liga o Chromebook ao projetor/TV e instala a extensão. Com este app
no celular, ele controla a tela projetada **sem voltar à mesa** — andando pela
sala.

A **primeira função** prevista é **enviar uma URL / abrir uma aba**: o professor
digita ou escolhe um site no celular e ele abre na hora no Chromebook.

## Como funciona (resumo)

- Comunicação **direta entre celular e Chromebook**, pela **rede local** da escola.
- Sem servidor central e **sem nuvem** — usa **WebRTC (DataChannel)**.
- O pareamento é por **QR code** (handshake de dois QR codes). Veja
  [`docs/protocolo.md`](docs/protocolo.md).

```
┌─────────────┐   comando (JSON)    ┌──────────────────────┐
│  Celular    │ ──────────────────► │  Chromebook          │
│  (este app) │   WebRTC DataChannel│  (extensão)          │
│  controle   │ ◄────────────────── │  abre a aba/URL      │
└─────────────┘        ACK          └──────────────────────┘
        \_______________ rede local da escola _______________/
```

Detalhes em [`docs/arquitetura.md`](docs/arquitetura.md).

## Estrutura do repositório

```
chromebook-controller-app/
├── lib/
│   ├── main.dart                 # ponto de entrada
│   └── src/
│       ├── pairing/             # leitura do QR e geração do QR de resposta
│       ├── webrtc/            # cliente WebRTC (papel "answerer")
│       ├── commands/         # modelos de mensagem (protocolo)
│       └── ui/             # telas
├── android/             # projeto Android (org: pro.omanoloneto)
├── test/               # testes
├── docs/              # documentação (arquitetura, protocolo, instalação)
├── pubspec.yaml
└── README.md
```

> **Plataforma:** Android, com applicationId `pro.omanoloneto.controle_de_aula`.
> Para rodar, veja [`docs/instalacao.md`](docs/instalacao.md).

## Tecnologias previstas

- **Flutter / Dart**
- **WebRTC** via [`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc)
- **Leitura de QR** via [`mobile_scanner`](https://pub.dev/packages/mobile_scanner)
- **Geração de QR** via [`qr_flutter`](https://pub.dev/packages/qr_flutter)

(Pacotes listados como pretendidos; ainda não fixados.)

## Roteiro

- [x] Pareamento por QR code (handshake WebRTC sem servidor)
- [x] Comando **abrir URL / nova aba** (função prioritária)
- [x] Tela inicial com campo de URL
- [x] Indicador de status da conexão
- [ ] Atalhos de sites favoritos
- [ ] Comandos futuros: bloquear/liberar tela, mensagem na tela, fechar abas

## Contribuindo

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Toda a documentação do projeto é em
português.

## Licença

[MIT](LICENSE) © 2026 Mano Afonso (@omanoloneto)
