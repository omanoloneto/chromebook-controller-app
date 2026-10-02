// Tabela única de erros em português (SPEC-turma §6.2; a mesma do desktop,
// teacher/textos_erro.py). O código cru do ack nunca aparece para o
// professor: só o texto daqui. Puro — testável (test/textos_erro_test.dart).

import '../commands/command.dart';
import '../util/versao.dart';

/// Escrita nova negada pelas rules (console ainda com as rules antigas).
const String kTextoServidorDesatualizado =
    'O servidor da escola ainda não foi atualizado para este recurso. Avise '
    'quem cuida do sistema.';

/// Escrita que falhou por falta de rede.
const String kTextoSemInternet = 'Sem conexão com a internet. Tente de novo.';

/// PC desligado ou sem internet no envio.
const String kTextoOffline = 'Desligado ou sem internet.';

/// Nada voltou do PC em 25 s.
const String kTextoTimeout = 'Não respondeu a tempo.';

const String _textoGenerico = 'Não foi possível concluir neste computador.';

/// Texto ao professor para o [codigo] de erro de um ack (ou de `aplicado`).
/// [tipoComando] e [ext] (meta/ext do PC) distinguem o `tipo_desconhecido` de
/// um comando só do Celita num Chromebook do de um PC desatualizado.
String textoErro(String? codigo, {String? tipoComando, String? ext}) {
  final c = codigo?.trim() ?? '';
  switch (c) {
    case 'sem_sessao':
      return 'Ninguém está logado neste computador agora.';
    case 'url_invalida':
      return 'O endereço do site não é válido.';
    case 'payload_invalido':
      return 'O pedido chegou incompleto. Tente de novo.';
    case 'tipo_desconhecido':
      if (tipoComando != null &&
          kComandosSoCelita.contains(tipoComando) &&
          !temCelita(ext)) {
        return 'Isso só funciona nos computadores com Celita OS.';
      }
      return 'Este computador tem uma versão antiga — atualize-o.';
    case 'so_chromeos':
      return 'Isso só funciona em Chromebook.';
    case 'blob_invalido':
      return 'A imagem enviada está corrompida.';
    case 'imagem_grande':
      return 'A imagem é grande demais.';
    case 'ponte_caiu':
      return 'O navegador do aluno se desconectou — peça para reabrir.';
    case 'ponte_sem_resposta':
    case 'sem_resposta':
      return 'O navegador do aluno não respondeu a tempo.';
    case 'resposta_invalida':
    case 'cmd_desconhecido':
      return 'O computador respondeu de forma inesperada.';
    case 'atualizador_ausente':
      return 'Este computador não tem o atualizador do Celita.';
    case 'aba_falhou':
      return 'Não foi possível abrir o site no computador.';
    case 'fechar_falhou':
      return 'Não foi possível fechar as abas no computador.';
    case 'sem_notifications':
      return 'Não foi possível mostrar a mensagem na tela do aluno.';
    case 'classview_falhou':
      return 'Não foi possível atualizar a visão da turma no telão.';
    case 'snapshot_upload':
      return 'Não foi possível enviar a imagem do computador.';
    case 'numero_invalido':
      return 'Número de unidade inválido (use de 1 a 9999).';
  }
  if (c.startsWith('voges_')) return 'Não foi possível abrir o site no computador.';
  if (c.startsWith('tela_')) {
    return 'Não foi possível capturar a tela deste computador.';
  }
  if (c.startsWith('camera_')) {
    return 'Não foi possível usar a câmera deste computador.';
  }
  if (c.startsWith('papel_')) return 'Não foi possível trocar o papel de parede.';
  if (c.startsWith('aviso_')) {
    return 'Não foi possível mostrar a mensagem na tela do aluno.';
  }
  if (c.startsWith('chat_')) return 'Não foi possível entregar a mensagem.';
  return _textoGenerico; // executor_falhou e qualquer outro
}

/// Erro de uma ESCRITA nova (state/lock|exam|monitor, apagar up/thumbs,
/// stores): negada pelas rules vira o aviso de servidor desatualizado; o
/// resto, falta de internet. O professor nunca vê sucesso quando a escrita
/// foi negada. [codigo] = `FirebaseException.code` (ou null).
String textoErroDeEscrita(String? codigo) {
  final c = codigo ?? '';
  if (c == 'permission-denied' || c.contains('permission') || c == '401' || c == '403') {
    return kTextoServidorDesatualizado;
  }
  return kTextoSemInternet;
}
