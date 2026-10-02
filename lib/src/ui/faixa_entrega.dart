// Faixas de confirmação (itens 24, 25 e 26):
// - FaixaEntrega: o último envio da turma (ou para um PC). Fica no topo da
//   tela como MaterialBanner ("Enviando… 3 de 20") até tudo resolver ou até
//   25 s, e então vira um SnackBar de 4 s com o texto final;
// - FaixaEstadoTurma: "Olhos em mim" e modo prova enquanto ligados ("Telas
//   travadas: 18 de 20 · 2 desligados · desde 10:42").
// Tocar em qualquer uma abre a lista por PC ("Unidade 3 · Ana — Recebeu ✓").
// O professor nunca vê "recebeu ✓" por suposição: só por ack ou `aplicado`.
// Ver SPEC-turma §6.3, §7.4 e §8.4.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/entrega.dart';
import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import '../util/natural_sort.dart';
import '../util/versao.dart';
import 'theme.dart';

// ---- Estado refeito do banco (puro) ---------------------------------------------

/// Um PC da turma com trava (ou prova) ligada no estado gravado, visto pelo
/// último `aplicado` do relatório dele.
class PcNoEstado {
  const PcNoEstado({
    required this.deviceId,
    required this.online,
    required this.suportaTurma,
    this.aplicado,
  });

  final String deviceId;
  final bool online;
  final bool suportaTurma;

  /// `aplicado.trava` (ou `.prova`) do último relatório; null = não veio.
  final EstadoAplicado? aplicado;
}

/// A confirmação de "Olhos em mim"/modo prova refeita a partir do estado: o
/// app reiniciado não tem a [Entrega] da hora em que ligou, e um PC que entrou
/// depois na aula também não está nela. PC desligado conta como desligado;
/// versão antiga, como versão antiga; o resto, pelo `aplicado` (ligado =
/// recebeu, erro = o código, sem confirmação = "não travou"/"não entrou").
Entrega entregaDoEstado(
  TipoEntrega tipo,
  Iterable<PcNoEstado> pcs, {
  DateTime? agora,
}) {
  final t0 = agora ?? DateTime.now();
  final e = Entrega(tipo: tipo, enviadoEm: t0, alvoOn: true);
  for (final p in pcs) {
    e.adicionar(
      p.deviceId,
      online: p.online,
      suportaTurma: p.suportaTurma,
      comandoNovo: true,
    );
    final a = p.aplicado;
    if (p.online && p.suportaTurma && a != null) {
      e.aoAplicado(
        p.deviceId,
        tipo == TipoEntrega.trava ? Aplicado(trava: a) : Aplicado(prova: a),
      );
    }
  }
  e.aoTempo(t0.add(e.timeout)); // sem confirmação: não aplicou
  return e;
}

/// A confirmação de "Olhos em mim" (ou do modo prova) dos PCs da turma agora.
Entrega entregaDoEstadoDaTurma(PairingController pairing, TipoEntrega tipo) {
  final trava = tipo == TipoEntrega.trava;
  return entregaDoEstado(tipo, [
    for (final id in pairing.pcsDaTurma)
      if (trava ? pairing.telaTravada(id) : pairing.provaNoPc(id))
        if (pairing.pcPorId(id) case final s?)
          PcNoEstado(
            deviceId: id,
            online: pairing.isOnline(s),
            suportaTurma: suportaTurma(s.versaoExt),
            aplicado: trava ? s.aplicado?.trava : s.aplicado?.prova,
          ),
  ]);
}

// ---- Detalhes (bottom sheet) -----------------------------------------------------

int _gravidade(EstadoEntregaPc e) => switch (e) {
      EstadoEntregaPc.erro => 0,
      EstadoEntregaPc.semResposta => 1,
      EstadoEntregaPc.versaoAntiga => 2,
      EstadoEntregaPc.desligado => 3,
      EstadoEntregaPc.enviando => 4,
      EstadoEntregaPc.recebeu => 5,
    };

/// Lista por PC ("Unidade 3 · Ana — Recebeu ✓"), quem não recebeu primeiro.
/// [entrega] é relida a cada mudança (o PC que liga atualiza ao vivo).
Future<void> mostrarDetalhesEntrega(
  BuildContext context,
  PairingController pairing, {
  required String titulo,
  required Entrega? Function() entrega,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: pairing,
          builder: (ctx, _) {
            final e = entrega();
            final pcs = e == null ? <EntregaPc>[] : [...e.pcs];
            pcs.sort((a, b) {
              final g = _gravidade(a.estado).compareTo(_gravidade(b.estado));
              if (g != 0) return g;
              return compararNatural(
                pairing.nomeDoPc(a.deviceId),
                pairing.nomeDoPc(b.deviceId),
              );
            });
            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title:
                      Text(titulo, style: Theme.of(ctx).textTheme.titleMedium),
                ),
                const Divider(height: 1),
                if (pcs.isEmpty)
                  const ListTile(title: Text('Nenhum computador nesta lista.')),
                for (final p in pcs)
                  ListTile(
                    dense: true,
                    leading: _IconeDoEstado(p.estado),
                    title: Text(pairing.textoDaEntregaNoPc(e!, p)),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _IconeDoEstado extends StatelessWidget {
  const _IconeDoEstado(this.estado);

  final EstadoEntregaPc estado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = cores(context);
    return switch (estado) {
      EstadoEntregaPc.recebeu => Icon(Icons.check_circle, color: c.online),
      EstadoEntregaPc.enviando => const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      EstadoEntregaPc.desligado =>
        Icon(Icons.power_settings_new, color: c.offline),
      EstadoEntregaPc.semResposta =>
        Icon(Icons.hourglass_disabled, color: c.atencao),
      EstadoEntregaPc.versaoAntiga =>
        Icon(Icons.system_update_alt, color: c.atencao),
      EstadoEntregaPc.erro => Icon(Icons.error_outline, color: scheme.error),
    };
  }
}

// ---- Faixa de um envio (MaterialBanner → SnackBar) -------------------------------

// Cada envio vira SnackBar UMA vez, mesmo com mais de uma tela olhando.
final Expando<bool> _finalMostrado = Expando<bool>('faixa');

/// Faixa da confirmação do último envio. [deviceId] null = envios da turma
/// (aba Aula); senão, só o envio para aquele PC (tela do PC).
class FaixaEntrega extends StatefulWidget {
  const FaixaEntrega({
    super.key,
    required this.pairing,
    this.deviceId,
    this.cartao = false,
  });

  final PairingController pairing;
  final String? deviceId;

  /// Dentro de uma lista com margem (tela do PC): cantos arredondados e
  /// espaço embaixo, só enquanto aparece.
  final bool cartao;

  @override
  State<FaixaEntrega> createState() => _FaixaEntregaState();
}

class _FaixaEntregaState extends State<FaixaEntrega> {
  PairingController get _p => widget.pairing;

  // Envio que esta faixa mostrou ainda em andamento: só ele vira SnackBar
  // (abrir a tela depois não repete o aviso de um envio antigo).
  Entrega? _acompanhando;

  // Último envio visto: um envio NOVO que já nasce resolvido (todos os PCs
  // desligados) vira SnackBar na hora, sem banner.
  Entrega? _visto;

  @override
  void initState() {
    super.initState();
    _visto = _minha;
    _p.addListener(_onChange);
  }

  @override
  void didUpdateWidget(FaixaEntrega old) {
    super.didUpdateWidget(old);
    if (old.pairing != widget.pairing) {
      old.pairing.removeListener(_onChange);
      widget.pairing.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _p.removeListener(_onChange);
    super.dispose();
  }

  Entrega? get _minha {
    final e = _p.entrega;
    if (e == null) return null;
    final umPc = _p.entregaUmPc;
    final daqui =
        widget.deviceId == null ? umPc == null : umPc == widget.deviceId;
    return daqui ? e : null;
  }

  void _onChange() {
    if (!mounted) return;
    final e = _minha;
    if (e != null && !identical(e, _visto)) {
      _visto = e;
      _acompanhando = e; // envio novo: acompanha até resolver
    }
    if (e != null && !e.resolvida) _acompanhando = e;
    if (e != null &&
        e.resolvida &&
        identical(e, _acompanhando) &&
        _finalMostrado[e] != true) {
      // Decide depois que a pilha atual termina: um envio pode avisar ainda
      // sendo montado, um PC por vez (o 1º desligado não é "tudo resolvido").
      scheduleMicrotask(() => _talvezFinal(e));
    }
    setState(() {});
  }

  void _talvezFinal(Entrega e) {
    if (!mounted ||
        !identical(_minha, e) ||
        !e.resolvida ||
        !identical(e, _acompanhando) ||
        _finalMostrado[e] == true) {
      return;
    }
    _finalMostrado[e] = true;
    _acompanhando = null;
    _mostrarFinal(e);
  }

  void _mostrarFinal(Entrega e) {
    final texto = _p.textoDaEntrega;
    if (texto == null) return;
    final todos = e.contar(EstadoEntregaPc.recebeu) == e.total;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          duration: const Duration(seconds: 4),
          persist: false, // com "Detalhes" também sai em 4 s
          action: todos || widget.deviceId != null
              ? null
              : SnackBarAction(
                  label: 'Detalhes',
                  onPressed: () => _detalhes(e),
                ),
        ),
      );
  }

  void _detalhes(Entrega e) => mostrarDetalhesEntrega(
        context,
        _p,
        titulo: 'Quem recebeu',
        entrega: () => e,
      );

  @override
  Widget build(BuildContext context) {
    final e = _minha;
    final mostrar = e != null && !e.resolvida;
    final scheme = Theme.of(context).colorScheme;
    Widget banner() {
      final b = MaterialBanner(
        key: const ValueKey('faixa-entrega'),
        backgroundColor: scheme.surfaceContainerHigh,
        padding: const EdgeInsetsDirectional.only(start: 16, top: 8, end: 8),
        leadingPadding: const EdgeInsetsDirectional.only(end: 12),
        leading: const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        content: Text(
          _p.textoDaEntrega ?? 'Enviando…',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _detalhes(e!),
            child: const Text('Detalhes'),
          ),
        ],
      );
      if (!widget.cartao) return b;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: b),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: mostrar ? banner() : const SizedBox(width: double.infinity),
    );
  }
}

// ---- Faixa de estado: "Olhos em mim" e modo prova --------------------------------

/// Faixa de "Olhos em mim" ([TipoEntrega.trava]) ou do modo prova
/// ([TipoEntrega.prova]): durante a confirmação mostra "Travando… 3 de 20";
/// ligado, o quadro de agora ("Telas travadas: 18 de 20 · 2 desligados ·
/// desde 10:42"). Ao destravar, o resultado vira SnackBar.
class FaixaEstadoTurma extends StatefulWidget {
  const FaixaEstadoTurma({
    super.key,
    required this.pairing,
    required this.tipo,
  });

  final PairingController pairing;
  final TipoEntrega tipo;

  @override
  State<FaixaEstadoTurma> createState() => _FaixaEstadoTurmaState();
}

class _FaixaEstadoTurmaState extends State<FaixaEstadoTurma> {
  PairingController get _p => widget.pairing;
  bool get _trava => widget.tipo == TipoEntrega.trava;

  // Destravar/desligar visto nascer aqui: vira SnackBar ao resolver (mesmo
  // que já nasça resolvido, com todos os PCs desligados).
  Entrega? _desligando;
  Entrega? _visto;

  Entrega? get _viva => _trava ? _p.entregaTrava : _p.entregaProva;
  bool get _ligado => _trava ? _p.travaLigada : _p.provaLigada;

  @override
  void initState() {
    super.initState();
    _visto = _viva;
    _p.addListener(_onChange);
  }

  @override
  void dispose() {
    _p.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final e = _viva;
    if (e != null && !identical(e, _visto)) {
      _visto = e;
      if (!e.alvoOn) _desligando = e;
    }
    if (e != null && !e.alvoOn && !e.resolvida) _desligando = e;
    if (e != null &&
        e.resolvida &&
        identical(e, _desligando) &&
        _finalMostrado[e] != true) {
      _finalMostrado[e] = true;
      _desligando = null;
      final todos = e.contar(EstadoEntregaPc.recebeu) == e.total;
      // Prova: o "Modo prova desligado." com "Desfazer" já está na tela; só
      // o substitui quando algum PC ficou para trás.
      if (_trava || !todos) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_trava ? textoTrava(e) : textoProva(e)),
              duration: const Duration(seconds: 4),
              persist: false,
              action: todos
                  ? null
                  : SnackBarAction(
                      label: 'Detalhes',
                      onPressed: () => _detalhes(() => e),
                    ),
            ),
          );
      }
    }
    setState(() {});
  }

  void _detalhes(Entrega? Function() entrega) => mostrarDetalhesEntrega(
        context,
        _p,
        titulo: _trava ? 'Telas travadas' : 'Modo prova',
        entrega: entrega,
      );

  @override
  Widget build(BuildContext context) {
    final viva = _viva;
    String? texto;
    var andamento = false;
    Entrega? Function()? detalhe;
    if (viva != null && !viva.resolvida) {
      texto = _trava ? _p.textoDaTrava : _p.textoDaProva;
      andamento = true;
      detalhe = () => _viva;
    } else if (_ligado) {
      final e = entregaDoEstadoDaTurma(_p, widget.tipo);
      if (e.total > 0) {
        texto = _trava ? textoTrava(e, desde: _p.travaDesde) : textoProva(e);
        detalhe = () => entregaDoEstadoDaTurma(_p, widget.tipo);
      }
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: texto == null
          ? const SizedBox(width: double.infinity)
          : _Faixa(
              icone: _trava ? Icons.lock_outline : Icons.fact_check_outlined,
              texto: texto,
              andamento: andamento,
              forte: _trava,
              onTap: () => _detalhes(detalhe!),
            ),
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({
    required this.icone,
    required this.texto,
    required this.andamento,
    required this.forte,
    required this.onTap,
  });

  final IconData icone;
  final String texto;
  final bool andamento;

  /// Trava: cor cheia (a turma está parada); prova: tom suave.
  final bool forte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fundo = forte ? scheme.primary : scheme.secondaryContainer;
    final frente = forte ? scheme.onPrimary : scheme.onSecondaryContainer;
    return Material(
      color: fundo,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              if (andamento)
                SizedBox.square(
                  dimension: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: frente),
                )
              else
                Icon(icone, size: 20, color: frente),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: frente,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.chevron_right, color: frente),
            ],
          ),
        ),
      ),
    );
  }
}
