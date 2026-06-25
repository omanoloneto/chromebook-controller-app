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

## Uso (sem QR)

1. Abra o app — ele inicia o servidor local (porta 47615) e mostra o seu `ip:porta`.
2. Os Chromebooks com a extensão **se descobrem sozinhos** e aparecem na lista
   ("online"). O 1º professor a encontrar cada PC fica vinculado a ele (TOFU).
3. Digite/cole uma URL → **"Abrir na turma toda"** (todos) ou toque no ícone de um
   PC para abrir só nele.

> Mantenha o app **aberto** (servidor em foreground). A conexão é direta e
> **criptografada**; a chave é derivada por X25519 (nunca trafega). Detalhes em
> [`protocolo.md`](protocolo.md).

## Problemas comuns

- **Nenhum PC aparece:** mesma **Wi-Fi**, **sem client isolation**. No Chromebook,
  abra `http://<ip-do-celular>:47615/` (o `ip` aparece no app) numa aba — deve
  responder um JSON com `"app":"controle-de-aula"`. Se não, é a rede (isolamento)
  ou o app não está aberto.
- **Descoberta lenta/atípica:** no popup da extensão, informe o **IP do celular**
  manualmente.
- **"Sem Wi-Fi detectado":** conecte o celular ao Wi-Fi da escola (não dados
  móveis — precisa estar na mesma LAN dos Chromebooks).
