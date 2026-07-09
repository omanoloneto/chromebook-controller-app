# Instalação — App (desenvolvimento)

> O app ainda **não está na Play Store**. Por enquanto, roda via Flutter em
> modo de desenvolvimento.

## Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado
  (`flutter --version`).
- Android Studio ou apenas o Android SDK + um celular/emulador Android.
- Este repositório clonado.
- **Internet** no celular (Wi-Fi ou dados móveis) — o transporte é Firebase;
  celular e Chromebooks **não precisam** estar na mesma rede.

## Projeto Firebase (checklist do console)

O projeto é o `controle-de-aula-f53bd`. No [console](https://console.firebase.google.com):

1. **Authentication → Sign-in method → Anônimo: ATIVADO.**
2. **Contas anônimas nunca podem ser apagadas.** No Auth padrão (este projeto)
   não há limpeza automática — nada a fazer. ⚠️ Se um dia fizer upgrade para
   "Authentication with Identity Platform", a opção "Automatic clean-up"
   aparece e deve ficar **OFF** (ligada, apaga anônimas +30 dias → a turma
   inteira precisa re-parear).
3. **Realtime Database** criado (instância default,
   `https://controle-de-aula-f53bd-default-rtdb.firebaseio.com`).
4. **Security Rules publicadas** ✔ (feito em 2026-07-07). Para republicar após
   alterar `firebase/database.rules.json`:
   `cd firebase && firebase deploy --only database --project controle-de-aula-f53bd`.

A config do app está em `lib/firebase_options.dart`, gerada pelo
`flutterfire configure` com o **app Android registrado** no console
(`1:305628431439:android:…`). Sem `google-services.json`/plugin gradle —
inicialização via Dart.

## Plataforma Android

O projeto **já inclui** a pasta `android/` (applicationId
`pro.omanoloneto.controle_de_aula`). Não é preciso gerar nada.

## Instalando as dependências

```bash
flutter pub get
```

## Rodando no celular

1. Ative a **depuração USB** no celular e conecte-o (ou inicie um emulador).
2. Confirme que o aparelho aparece em `flutter devices`.
3. Rode:

```bash
flutter run
```

## Uso (pareamento por QR)

1. Abra o app — ele autentica no Firebase e mostra a lista (vazia no 1º uso).
2. Em cada Chromebook, abra o **popup da extensão** (ou "QR em tela cheia") —
   aparece um **QR de pareamento**.
3. No app, toque em **⌗ (escanear QR)** e aponte a câmera para o QR de cada
   Chromebook. O scanner fica aberto: dá para parear a turma toda em sequência.
   O pareamento é **1x por PC**; depois o PC conecta sozinho, de qualquer rede.
4. Digite/cole uma URL → **"Abrir na turma toda"** (todos) ou toque no ícone de
   um PC para abrir só nele.
5. Cada cartão mostra a **aba ativa** do aluno; toque para ver **abas abertas +
   histórico** (somente URLs/títulos, sem captura de tela; dados só na memória).
6. Segure (long-press) um PC — ou use o lápis na tela de detalhe — para dar o
   **nome do aluno** (fica salvo no celular).
7. **Favoritos** (⭐): cadastre os sites da aula; viram chips na home (toque
   preenche a URL; segure para abrir/fechar na turma).
8. **Regras** (🛡): **Bloquear** impede o site nos Chromebooks (página "Site
   bloqueado pelo professor"; vale na hora e persiste offline); **Alertar**
   deixa o cartão do aluno vermelho aqui no app.
9. **Papel de parede** (🖼): escolha uma imagem da galeria e aplique na turma
   (só funciona em ChromeOS de verdade).
10. No 1º uso o app pede **permissão de notificação** — é a notificação do
    serviço ("N PCs conectados"), que mantém tudo funcionando **com a tela
    apagada**. Negar não derruba o serviço; só esconde a notificação. Também
    pede **câmera** (só para escanear o QR).

> A comunicação é **criptografada ponta-a-ponta** (X25519 → AES-256-GCM): o
> Firebase só carrega envelopes cifrados. Detalhes em [`protocolo.md`](protocolo.md).

## Problemas comuns

- **"Não foi possível conectar ao Firebase":** verifique a internet do celular
  e se a **Auth anônima** está ativada no console.
- **"QR expirado":** o token do QR é de uso único — abra o popup da extensão de
  novo (ele gera outro QR) e re-escaneie.
- **"PC vinculado a outro professor":** o vínculo é exclusivo (TOFU). No
  Chromebook: popup → **"Desvincular professor"**, depois escaneie o QR novo.
- **Reinstalei o app e os PCs não conectam:** a reinstalação perde a identidade
  do professor. Recovery: desvincular cada PC pelo popup e re-parear por QR.
- **PC "offline" na lista:** o Chromebook está sem internet, com a tampa
  fechada, ou o aluno desativou a extensão.
