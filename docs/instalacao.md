# Instalação — App (desenvolvimento)

> O app ainda **não está na Play Store**. Por enquanto, roda via Flutter em
> modo de desenvolvimento.

## Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado
  (`flutter --version`).
- Android Studio ou apenas o Android SDK + um celular/emulador Android.
- Este repositório clonado.

## Plataforma Android

O projeto **já inclui** a pasta `android/`, gerada com a organização
`pro.omanoloneto` (applicationId `pro.omanoloneto.controle_de_aula`). Não é
preciso gerar nada.

Se algum dia precisar **regenerar** os arquivos de plataforma (ou adicionar
outra, como iOS), rode na raiz — o comando **não apaga** o que existe em `lib/`:

```bash
flutter create --org pro.omanoloneto --project-name controle_de_aula --platforms=android .
```

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
