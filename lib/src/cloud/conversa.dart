// Conversas e Recados do professor (itens 27 e 29): o que fica em memória por
// PC (PcSession.chat, .pedidos, .maoEm) e as legendas dos balões. Nada disso
// vai ao banco além do cmd/up transitório. Ver SPEC-turma §3.2, §3.6 e §4.4.

import '../ui/textos_erro.dart';

enum AutorChat { professor, aluno, sistema }

/// Código interno do balão quando a escrita no banco falhou NESTE celular
/// (não veio do PC): a legenda vira o texto de falta de internet.
const String kErroEnvioLocal = 'envio_local';

/// Situação do balão do professor (legenda embaixo dele).
enum EstadoBalao {
  enviando,
  entregue,
  aguardando, // PC desligado no envio; vira "entregue" quando o ack chegar
  ninguemLogado, // ack sem_sessao: não fica para a próxima sessão
  erro,
  semResposta, // 25 s sem ack com o PC ligado (ack tardio ainda corrige)
}

class ChatItem {
  ChatItem({
    required this.id,
    required this.autor,
    required this.texto,
    required this.ts,
    this.cmdId,
    this.estado,
    this.codigoErro,
    this.paraTurma = false,
    this.versaoAntiga = false,
  });

  /// `mid` da mensagem (dedup por PC).
  final String id;
  final AutorChat autor;
  final String texto;

  /// Hora em ms do servidor (aluno: a do push id; professor: a do envio).
  final int ts;

  /// Professor: id do comando, para casar o ack (ou `aplicado.acks`).
  final String? cmdId;
  EstadoBalao? estado;
  String? codigoErro;

  /// Enviada pelo "Mensagem para a turma".
  final bool paraTurma;

  /// PC antigo: foi como `show_message` e o aluno não tem como responder.
  final bool versaoAntiga;
}

/// Legenda do balão do professor (§3.6). [ext] = meta/ext do PC.
String legendaDoBalao(ChatItem item, {String? ext}) {
  final partes = <String>[];
  switch (item.estado) {
    case EstadoBalao.enviando:
      partes.add('Enviando…');
    case EstadoBalao.entregue:
      partes.add('✓ Entregue');
    case EstadoBalao.aguardando:
      partes.add('Aguardando (PC desligado)');
    case EstadoBalao.ninguemLogado:
      partes.add('Ninguém logado — não entregue');
    case EstadoBalao.erro:
      partes.add(
        item.codigoErro == kErroEnvioLocal
            ? kTextoSemInternet
            : textoErro(item.codigoErro, ext: ext),
      );
    case EstadoBalao.semResposta:
      partes.add('Não respondeu a tempo');
    case null:
      break;
  }
  if (item.paraTurma) partes.add('para a turma');
  if (item.versaoAntiga) partes.add('Versão antiga: o aluno não consegue responder');
  return partes.join(' · ');
}

/// Pedido de liberação em Recados. Pedidos repetidos do mesmo PC para o mesmo
/// site colapsam numa entrada (hora e motivo do mais novo; todos os mids são
/// apagados ao agir).
class PedidoLiberacao {
  PedidoLiberacao({
    required this.deviceId,
    required this.mid,
    required this.site,
    required this.url,
    required this.motivo,
    required this.bloqueio,
    required this.ts,
  }) : mids = {mid};

  final String deviceId;
  String mid; // o mais novo: vai no unblock_result
  final String site;
  String url;
  String motivo;
  String bloqueio; // 'regra' | 'prova'
  int ts; // ms do servidor (push id)
  final Set<String> mids;

  /// Junta um pedido repetido (mesmo PC e site): vale o mais novo.
  void juntar({
    required String mid,
    required String url,
    required String motivo,
    required String bloqueio,
    required int ts,
  }) {
    mids.add(mid);
    if (ts >= this.ts) {
      this.mid = mid;
      this.url = url;
      this.motivo = motivo;
      this.bloqueio = bloqueio;
      this.ts = ts;
    }
  }
}

/// "10:42" no fuso do celular.
String horaMinuto(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Linha fixa em Recados para o PC silenciado por excesso de mensagens.
const String kTextoSilenciado =
    'Muitas mensagens deste computador — silenciado por 10 min';
