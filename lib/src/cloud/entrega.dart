// Confirmação de entrega (item 26): agrega, por PC, o que aconteceu com um
// comando de turma ou com uma mudança de estado (trava, prova) e monta os
// textos da faixa. Puro (sem Firebase) — igual ao teacher/entrega.py do
// desktop e testável em test/entrega_test.dart. Ver SPEC-turma §6.
//
// Regra de ouro: o professor nunca vê "recebeu ✓" por suposição. A fonte é o
// ack do id emitido ou o `aplicado` do relatório do PC.

import '../commands/command.dart';
import '../ui/textos_erro.dart';

/// O que se sabe de um PC dentro de uma [Entrega].
enum EstadoEntregaPc { enviando, recebeu, erro, desligado, semResposta, versaoAntiga }

/// Comando one-shot (ack) ou estado (confirmado pelo `aplicado`).
enum TipoEntrega { comando, trava, prova }

class EntregaPc {
  EntregaPc({required this.deviceId, required this.estado, this.cmdId});

  final String deviceId;

  /// Id do comando emitido para este PC (comando one-shot); null em estado.
  final String? cmdId;
  EstadoEntregaPc estado;

  /// Código do erro (ack ou `aplicado.*.erro`) quando [estado] é erro.
  String? codigo;
}

class Entrega {
  Entrega({
    required this.tipo,
    required this.enviadoEm,
    this.tipoComando,
    this.alvoOn = true,
    this.revEnviado = 0,
    this.timeout = kEntregaTimeout,
  });

  final TipoEntrega tipo;
  final DateTime enviadoEm;

  /// `type` do comando (só para o texto de `tipo_desconhecido`).
  final String? tipoComando;

  /// Trava/prova: o estado pedido (true = ligar) e o `rev` da escrita que
  /// mudou on/off (renovações não reiniciam a contagem).
  final bool alvoOn;
  final int revEnviado;
  final Duration timeout;

  final Map<String, EntregaPc> _pcs = {};

  List<EntregaPc> get pcs => List.unmodifiable(_pcs.values);

  EntregaPc? pc(String deviceId) => _pcs[deviceId];

  /// Põe um PC na entrega. Offline no envio começa "desligado"; PC que não
  /// entende recurso novo ([comandoNovo]) começa "versão antiga".
  void adicionar(
    String deviceId, {
    String? cmdId,
    required bool online,
    required bool suportaTurma,
    bool comandoNovo = false,
  }) {
    final EstadoEntregaPc estado;
    if (comandoNovo && !suportaTurma) {
      estado = EstadoEntregaPc.versaoAntiga;
    } else if (!online) {
      estado = EstadoEntregaPc.desligado;
    } else {
      estado = EstadoEntregaPc.enviando;
    }
    _pcs[deviceId] = EntregaPc(deviceId: deviceId, estado: estado, cmdId: cmdId);
  }

  /// Ack de um id emitido, vindo do PC [deviceId] (o ack é decifrado com a
  /// chave dele). Ack tardio SEMPRE corrige (depois do timeout, de
  /// "desligado", de "versão antiga"). true = mudou algo.
  bool aoAck(String deviceId, String id, {required bool ok, String? error}) {
    final p = _pcs[deviceId];
    if (p != null && p.cmdId == id) {
      return _marcar(p, ok ? EstadoEntregaPc.recebeu : EstadoEntregaPc.erro,
          ok ? null : (error ?? 'executor_falhou'),);
    }
    return false;
  }

  /// Relatório de um PC com `aplicado`: acks repetidos contam como ack (um
  /// app antigo pode ter apagado o ack antes); trava/prova confirmam pelo
  /// estado realmente aplicado.
  bool aoAplicado(String deviceId, Aplicado aplicado) {
    final p = _pcs[deviceId];
    if (p == null) return false;
    if (tipo == TipoEntrega.comando) {
      for (final a in aplicado.acks) {
        if (a.id == p.cmdId) {
          return _marcar(p, a.ok ? EstadoEntregaPc.recebeu : EstadoEntregaPc.erro,
              a.ok ? null : (a.error ?? 'executor_falhou'),);
        }
      }
      return false;
    }
    final e = tipo == TipoEntrega.trava ? aplicado.trava : aplicado.prova;
    if (e == null || e.rev < revEnviado) return false;
    if (e.erro != null) return _marcar(p, EstadoEntregaPc.erro, e.erro);
    if (e.on != alvoOn) return false; // outro professor já mudou depois
    return _marcar(p, EstadoEntregaPc.recebeu, null);
  }

  /// Passou o [timeout] sem confirmação: PC online "enviando" vira "sem
  /// resposta" (em estado: "não travou"/"não entrou"). true = mudou algo.
  bool aoTempo(DateTime agora) {
    if (agora.difference(enviadoEm) < timeout) return false;
    var mudou = false;
    for (final p in _pcs.values) {
      if (p.estado == EstadoEntregaPc.enviando) {
        p.estado = EstadoEntregaPc.semResposta;
        mudou = true;
      }
    }
    return mudou;
  }

  bool _marcar(EntregaPc p, EstadoEntregaPc estado, String? codigo) {
    if (p.estado == estado && p.codigo == codigo) return false;
    p.estado = estado;
    p.codigo = codigo;
    return true;
  }

  /// Nenhum PC aguardando a primeira resposta.
  bool get resolvida => !_pcs.values.any((p) => p.estado == EstadoEntregaPc.enviando);

  int get total => _pcs.length;
  int contar(EstadoEntregaPc e) => _pcs.values.where((p) => p.estado == e).length;
  int contarErro(String codigo) => _pcs.values
      .where((p) => p.estado == EstadoEntregaPc.erro && p.codigo == codigo)
      .length;
}

// ---- Textos (SPEC-turma §6.3, §7.4, §8.4) -------------------------------------

String _plural(int n, String um, String varios) => n == 1 ? um : varios;

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Faixa de um comando de turma: "Enviando… 3 de 20" e, no fim,
/// "✓ Todos receberam (20)" ou "✓ 18 de 20 receberam · 2 desligados
/// (recebem quando ligarem)".
String textoEntrega(Entrega e) {
  final m = e.total;
  final r = e.contar(EstadoEntregaPc.recebeu);
  if (!e.resolvida) return 'Enviando… $r de $m';
  if (r == m) return '✓ Todos receberam ($m)';
  final d = e.contar(EstadoEntregaPc.desligado);
  final s = e.contar(EstadoEntregaPc.semResposta);
  final er = e.contar(EstadoEntregaPc.erro);
  final v = e.contar(EstadoEntregaPc.versaoAntiga);
  final b = StringBuffer('✓ $r de $m receberam');
  if (d > 0) b.write(' · $d ${_plural(d, 'desligado', 'desligados')} (recebem quando ligarem)');
  if (s > 0) b.write(' · $s sem resposta');
  if (er > 0) b.write(' · $er com erro');
  if (v > 0) b.write(' · $v com versão antiga');
  return b.toString();
}

/// Faixa de um comando para UM PC: "{nome} recebeu ✓" etc.
String textoEntregaUmPc(Entrega e, String nome, {String? ext}) {
  final p = e.pcs.isEmpty ? null : e.pcs.first;
  if (p == null) return nome;
  switch (p.estado) {
    case EstadoEntregaPc.enviando:
      return 'Enviando para $nome…';
    case EstadoEntregaPc.recebeu:
      return '$nome recebeu ✓';
    case EstadoEntregaPc.desligado:
      return '$nome está desligado — recebe quando ligar';
    case EstadoEntregaPc.semResposta:
      return '$nome não respondeu a tempo';
    case EstadoEntregaPc.versaoAntiga:
      return '$nome: ${textoErro('tipo_desconhecido', ext: ext)}';
    case EstadoEntregaPc.erro:
      return '$nome: ${textoErro(p.codigo, tipoComando: e.tipoComando, ext: ext)}';
  }
}

/// Uma linha por PC do bottom sheet de detalhes ("Unidade 3 · Ana — {isto}").
String textoDoPc(Entrega e, EntregaPc p, {String? ext}) {
  final estado = e.tipo != TipoEntrega.comando;
  switch (p.estado) {
    case EstadoEntregaPc.enviando:
      return 'Enviando…';
    case EstadoEntregaPc.recebeu:
      if (e.tipo == TipoEntrega.trava) return e.alvoOn ? 'Tela travada ✓' : 'Tela destravada ✓';
      if (e.tipo == TipoEntrega.prova) {
        return e.alvoOn ? 'Em modo prova ✓' : 'Saiu do modo prova ✓';
      }
      return 'Recebeu ✓';
    case EstadoEntregaPc.desligado:
      return 'Desligado — recebe quando ligar';
    case EstadoEntregaPc.semResposta:
      if (estado && e.alvoOn) {
        return e.tipo == TipoEntrega.trava ? 'Não travou' : 'Não entrou no modo prova';
      }
      return kTextoTimeout;
    case EstadoEntregaPc.versaoAntiga:
      return 'Versão antiga — atualize este computador';
    case EstadoEntregaPc.erro:
      if (p.codigo == 'navegador_antigo') return 'Navegador desatualizado';
      return textoErro(p.codigo, tipoComando: e.tipoComando, ext: ext);
  }
}

/// Faixa da trava: "Telas travadas: 18 de 20 · 1 desligado · … · desde
/// 10:42"; durante a confirmação, "Travando… 3 de 20".
String textoTrava(Entrega e, {DateTime? desde}) {
  final m = e.total;
  final r = e.contar(EstadoEntregaPc.recebeu);
  if (!e.alvoOn) {
    if (!e.resolvida) return 'Destravando… $r de $m';
    return _comPartes('Telas destravadas: $r de $m', e, naoAplicou: (n) => '$n ${_plural(n, 'não destravou', 'não destravaram')}');
  }
  if (!e.resolvida) return 'Travando… $r de $m';
  final base = _comPartes(
    'Telas travadas: $r de $m',
    e,
    naoAplicou: (n) => '$n ${_plural(n, 'não travou', 'não travaram')}',
  );
  return desde == null ? base : '$base · desde ${_hhmm(desde)}';
}

/// Faixa do modo prova: "Modo prova: 18 de 20 · 1 desligado · 1 com o
/// navegador desatualizado".
String textoProva(Entrega e) {
  final m = e.total;
  final r = e.contar(EstadoEntregaPc.recebeu);
  if (!e.alvoOn) {
    if (!e.resolvida) return 'Desligando o modo prova… $r de $m';
    return _comPartes('Modo prova desligado: $r de $m', e,
        naoAplicou: (n) => '$n sem resposta',);
  }
  if (!e.resolvida) return 'Ligando o modo prova… $r de $m';
  return _comPartes(
    'Modo prova: $r de $m',
    e,
    naoAplicou: (n) => '$n ${_plural(n, 'não entrou', 'não entraram')}',
  );
}

String _comPartes(String base, Entrega e, {required String Function(int) naoAplicou}) {
  final d = e.contar(EstadoEntregaPc.desligado);
  final v = e.contar(EstadoEntregaPc.versaoAntiga);
  final z = e.contarErro('sem_sessao');
  final b = e.contarErro('navegador_antigo');
  final outros = e.contar(EstadoEntregaPc.erro) - z - b;
  final n = e.contar(EstadoEntregaPc.semResposta);
  final s = StringBuffer(base);
  if (d > 0) s.write(' · $d ${_plural(d, 'desligado', 'desligados')}');
  if (v > 0) s.write(' · $v com versão antiga');
  if (z > 0) s.write(' · $z sem ninguém logado');
  if (b > 0) s.write(' · $b com o navegador desatualizado');
  if (outros > 0) s.write(' · $outros com erro');
  if (n > 0) s.write(' · ${naoAplicou(n)}');
  return s.toString();
}
