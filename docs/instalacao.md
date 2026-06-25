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

## Uso

1. Abra o app — ele inicia o servidor local e mostra **1 QR** (e o `ip:porta`).
2. No **Chromebook**, abra a extensão → **Parear** → aponte a câmera para este QR.
3. Quando o Chromebook conectar, o app mostra o campo de URL.
4. Digite/cole uma URL e toque em **Abrir no Chromebook**.

> Mantenha o app **aberto** (o servidor roda em foreground). A conexão é direta e
> **criptografada** — a chave vai só no QR. Detalhes em [`protocolo.md`](protocolo.md).

## Problemas comuns

- **Chromebook não conecta:** mesma **Wi-Fi**, **sem client isolation**. Teste
  cru: no Chromebook, abra `http://<ip>:<porta>/` (mostrados no app) numa aba —
  deve responder `controle-de-aula`. Se não responder, é a rede (isolamento).
- **"Sem Wi-Fi detectado":** conecte o celular ao Wi-Fi da escola (não use só
  dados móveis — precisa estar na mesma LAN do Chromebook).
- **IP mudou:** se trocar de rede, o QR antigo expira; reabra o app e repareie.
