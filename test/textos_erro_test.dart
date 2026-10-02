// Tabela única de erros (SPEC-turma §6.2): toda linha, inclusive o
// tipo_desconhecido de comando só do Celita num Chromebook.

import 'package:controle_de_aula/src/commands/command.dart';
import 'package:controle_de_aula/src/ui/textos_erro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('códigos fixos', () {
    const tabela = {
      'sem_sessao': 'Ninguém está logado neste computador agora.',
      'url_invalida': 'O endereço do site não é válido.',
      'payload_invalido': 'O pedido chegou incompleto. Tente de novo.',
      'so_chromeos': 'Isso só funciona em Chromebook.',
      'blob_invalido': 'A imagem enviada está corrompida.',
      'imagem_grande': 'A imagem é grande demais.',
      'ponte_caiu': 'O navegador do aluno se desconectou — peça para reabrir.',
      'ponte_sem_resposta': 'O navegador do aluno não respondeu a tempo.',
      'sem_resposta': 'O navegador do aluno não respondeu a tempo.',
      'resposta_invalida': 'O computador respondeu de forma inesperada.',
      'cmd_desconhecido': 'O computador respondeu de forma inesperada.',
      'atualizador_ausente': 'Este computador não tem o atualizador do Celita.',
      'aba_falhou': 'Não foi possível abrir o site no computador.',
      'fechar_falhou': 'Não foi possível fechar as abas no computador.',
      'sem_notifications': 'Não foi possível mostrar a mensagem na tela do aluno.',
      'classview_falhou': 'Não foi possível atualizar a visão da turma no telão.',
      'snapshot_upload': 'Não foi possível enviar a imagem do computador.',
      'numero_invalido': 'Número de unidade inválido (use de 1 a 9999).',
      'executor_falhou': 'Não foi possível concluir neste computador.',
    };
    tabela.forEach((codigo, texto) => expect(textoErro(codigo), texto, reason: codigo));
  });

  test('famílias por prefixo', () {
    expect(textoErro('voges_fechado'), 'Não foi possível abrir o site no computador.');
    expect(textoErro('tela_vazia'), 'Não foi possível capturar a tela deste computador.');
    expect(textoErro('camera_NotAllowedError'), 'Não foi possível usar a câmera deste computador.');
    expect(textoErro('papel_falhou'), 'Não foi possível trocar o papel de parede.');
    expect(textoErro('aviso_falhou'), 'Não foi possível mostrar a mensagem na tela do aluno.');
    expect(textoErro('chat_falhou'), 'Não foi possível entregar a mensagem.');
  });

  test('qualquer outro código (e nulo) cai no genérico, nunca no código cru', () {
    for (final c in [null, '', 'TypeError: x is undefined', 'xyz']) {
      expect(textoErro(c), 'Não foi possível concluir neste computador.');
    }
  });

  test('tipo_desconhecido: comando só do Celita num Chromebook', () {
    for (final tipo in [MessageType.captureScreen, MessageType.liberarIas, MessageType.atualizar]) {
      expect(
        textoErro('tipo_desconhecido', tipoComando: tipo, ext: '0.6.0'),
        'Isso só funciona nos computadores com Celita OS.',
        reason: tipo,
      );
      expect(
        textoErro('tipo_desconhecido', tipoComando: tipo, ext: null),
        'Isso só funciona nos computadores com Celita OS.',
      );
    }
  });

  test('tipo_desconhecido nos demais casos: versão antiga', () {
    const antiga = 'Este computador tem uma versão antiga — atualize-o.';
    expect(textoErro('tipo_desconhecido'), antiga);
    expect(textoErro('tipo_desconhecido', tipoComando: MessageType.chatMessage, ext: '0.6.0'), antiga);
    // Comando do Celita num Celita velho: é versão antiga, não "só Celita".
    expect(
      textoErro('tipo_desconhecido', tipoComando: MessageType.atualizar, ext: 'celita-0.10.0'),
      antiga,
    );
  });

  test('escrita nova negada nunca vira sucesso; rede vira "sem conexão"', () {
    expect(textoErroDeEscrita('permission-denied'), kTextoServidorDesatualizado);
    expect(
      kTextoServidorDesatualizado,
      'O servidor da escola ainda não foi atualizado para este recurso. Avise '
      'quem cuida do sistema.',
    );
    expect(textoErroDeEscrita('unavailable'), kTextoSemInternet);
    expect(textoErroDeEscrita(null), kTextoSemInternet);
    expect(kTextoSemInternet, 'Sem conexão com a internet. Tente de novo.');
    expect(kTextoOffline, 'Desligado ou sem internet.');
    expect(kTextoTimeout, 'Não respondeu a tempo.');
  });
}
