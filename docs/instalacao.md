# Instalação — App (desenvolvimento)

> O app ainda **não está na Play Store**. Por enquanto, roda via Flutter em
> modo de desenvolvimento.

## Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado
  (`flutter --version`).
- Android Studio ou apenas o Android SDK + um celular/emulador Android.
- Este repositório clonado.

## Gerando os arquivos de plataforma

Este repositório versiona apenas `lib/`, `docs/` e a configuração. Os diretórios
de plataforma (`android/`, etc.) **não** estão versionados. Para criá-los sobre
o esqueleto, na raiz do projeto rode:

```bash
flutter create --org com.omanoloneto --project-name controle_de_aula .
```

> O comando preenche `android/`, `ios/`, etc., **sem apagar** o que já existe em
> `lib/`. Depois, confira o `pubspec.yaml` (já incluído aqui).

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

## Uso (quando implementado)

1. No Chromebook, a extensão mostra o **QR #1**.
2. No app, toque em **Parear** e escaneie o QR #1.
3. O app mostra o **QR #2**; aponte-o para a câmera do Chromebook.
4. Conectado! Digite/escolha uma URL e ela abre no Chromebook.

Detalhes do handshake em [`protocolo.md`](protocolo.md).

## Problemas comuns

- **Não conecta:** confirme que celular e Chromebook estão na **mesma rede
  Wi-Fi**. Redes de escola às vezes isolam aparelhos (*client isolation*); nesse
  caso, peça ao suporte de TI para liberar.
- **Câmera não abre:** confira a permissão de câmera do app nas configurações do
  Android.
