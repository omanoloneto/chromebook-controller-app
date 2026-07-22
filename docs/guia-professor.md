# Guia do Professor — Controle de Aula

Guia rápido para instalar e usar o app no seu celular Android. Nada aqui
exige conhecimento técnico.

## 1. Instalar o app

1. No celular, abra o link de download do APK (peça ao responsável ou baixe
   em: `github.com/omanoloneto/chromebook-controller-app/releases/latest`).
2. Toque no arquivo baixado (`app-release.apk`).
3. O Android vai avisar sobre "fontes desconhecidas": toque em
   **Configurações → Permitir desta fonte** e volte para concluir a
   instalação. (Isso aparece só na primeira vez.)
4. Abra o **Controle de Aula** e permita as **notificações** quando pedir.

**Atualizar**: baixe o APK novo no mesmo link e instale por cima — os dados
ficam.

## 2. Entrar no workspace da escola

Na primeira abertura o app oferece **"Entrar no workspace da escola"**:

1. Toque e entre com a sua conta **Google**.
2. Pronto — você já vê os PCs, turmas, regras de sites e histórico
   compartilhados pelos professores da escola.

(Se pulou essa tela: **Ajustes → Workspace da escola → Entrar**.)

Depois, em **Ajustes → Professor**, coloque o seu nome — é ele que aparece
nos avisos e nas travas de aula ("Em aula com Fulano").

## 3. Parear um Chromebook novo (uma vez por PC)

1. No Chromebook, clique no ícone azul da extensão **Controle de Aula** —
   aparece um QR.
2. No app, aba **Aula → botão de escanear** → aponte a câmera pro QR.
3. O PC ganha um número automático ("Unidade 7") e entra na lista de todos
   os professores. Para mudar o número: menu ⋮ do PC → **Alterar número da
   unidade** (número ocupado = os dois PCs trocam).

## 4. Dar aula

1. Aba **Turmas**: cadastre a turma e os alunos (compartilhado — se um colega
   já cadastrou, você já vê).
2. Aba **Aula → Iniciar aula** → escolha a turma.
3. Em cada PC da lista, **vincule o aluno** que está usando (dá para
   cadastrar um aluno novo na hora). Só PCs vinculados recebem os comandos
   da turma.
4. Comandos: **abrir site na turma**, fechar site, fechar todas as abas,
   bloquear sites (aba **Sites**), papel de parede, telão ("PC do professor"
   mostra a **Visão da turma** com o que cada aluno está vendo).
5. **Encerrar aula**: fecha o navegador dos PCs vinculados, desfaz os
   vínculos e libera os PCs para o próximo professor.

- Um PC só participa de **uma aula por vez**: se um colega já vinculou um
  aluno naquele PC, o app avisa "Em aula com {professor}".
- A **ficha do aluno** (aba Turmas → aluno) guarda as aulas e os sites
  acessados — visível a todos os professores, sempre criptografado no banco.

## 5. Extensão nos Chromebooks

Se os Chromebooks da escola são **gerenciados** (Google Admin Console), peça
ao administrador para **forçar a instalação** da extensão:

> Admin Console → Dispositivos → Chrome → Apps e extensões → Usuários e
> navegadores → adicionar pelo ID:
> `lhgjobopefkabgcifkkgmcnlmokjpjin`

Assim ela aparece sozinha em todos os PCs e se atualiza automaticamente —
nem professor nem aluno instalam nada.

Sem gerenciamento: instale pelo link da Chrome Web Store (não listada) em
cada Chromebook uma vez; as atualizações são automáticas.

## 6. Problemas comuns

| Sintoma | O que fazer |
|---------|-------------|
| Extensão "conectando…" sem parar | Ícone da extensão → botão **⟳** (reconectar). |
| PC não recebe comandos | Está vinculado na aula de outro professor? Encerrou a aula anterior? |
| "QR expirado" | Feche e reabra o popup da extensão (gera QR novo). |
| Troquei de celular | Instale o app, entre no workspace com o mesmo Google — tudo volta. |
