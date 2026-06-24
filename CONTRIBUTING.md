# Como contribuir

Obrigado pelo interesse em ajudar o **Controle de Aula**! Este projeto é
educacional e de código aberto. Toda a documentação e as discussões são em
**português**.

## Antes de começar

- Leia [`docs/arquitetura.md`](docs/arquitetura.md) e
  [`docs/protocolo.md`](docs/protocolo.md). O protocolo de mensagens é
  **compartilhado** com a extensão
  ([`chromebook-controller-extension`](https://github.com/omanoloneto/chromebook-controller-extension)).
  Qualquer mudança no protocolo precisa ser feita **nos dois repositórios**.

## Fluxo de trabalho

1. Faça um fork e crie um branch a partir de `main`:
   `git checkout -b minha-melhoria`
2. Rode `flutter analyze` e `flutter test` antes de commitar.
3. Faça commits pequenos e descritivos, em português.
4. Abra um Pull Request explicando **o quê** e **por quê**.

## Padrões

- **Commits:** mensagem no imperativo (ex.: `adiciona leitura de QR na tela inicial`).
- **Código:** comentários em português; siga o `flutter_lints`
  (ver `analysis_options.yaml`).
- **Formatação:** `dart format .` antes de abrir o PR.

## Reportando problemas

Abra uma *issue* com o passo a passo para reproduzir, o modelo do celular /
versão do Android e o que era esperado.
