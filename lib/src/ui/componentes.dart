// Peças da interface usadas em todas as telas: título de seção, cartão, grupo
// de opções, selo de status, botão de ação, número da unidade, estado vazio e
// os diálogos de confirmar e de pedir um texto. Tela nova usa estas, não
// monta a sua.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Tom de um selo ou botão; as cores saem do tema.
enum Tom { neutro, primario, sucesso, atencao, perigo }

({Color fundo, Color texto}) coresDoTom(BuildContext context, Tom tom) {
  final s = Theme.of(context).colorScheme;
  final c = cores(context);
  return switch (tom) {
    Tom.neutro => (fundo: s.surfaceContainerHighest, texto: s.onSurfaceVariant),
    Tom.primario => (fundo: s.primaryContainer, texto: s.onPrimaryContainer),
    Tom.sucesso => (fundo: c.sucessoBg, texto: c.online),
    Tom.atencao => (fundo: c.atencaoBg, texto: c.atencao),
    Tom.perigo => (fundo: c.alertaBg, texto: c.alertaFg),
  };
}

/// Título de uma seção: pequeno e forte, na cor secundária, com uma ação
/// opcional à direita ("Ver todos").
class TituloDeSecao extends StatelessWidget {
  const TituloDeSecao(
    this.texto, {
    super.key,
    this.acao,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 12, 8),
  });

  final String texto;
  final Widget? acao;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              texto,
              style: t.textTheme.labelMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (acao != null) acao!,
        ],
      ),
    );
  }
}

/// Cartão com borda fina e cantos de 16. Com [onTap], o cartão todo é tocável.
class Cartao extends StatelessWidget {
  const Cartao({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.onTap,
    this.cor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cor,
      margin: margin,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Opções agrupadas num cartão, com linha fina entre elas (Ajustes, ações
/// raras da tela do computador).
class GrupoDeOpcoes extends StatelessWidget {
  const GrupoDeOpcoes({super.key, required this.children, this.titulo});

  final List<Widget> children;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titulo != null) TituloDeSecao(titulo!),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Selo de status: ícone pequeno e texto numa pílula pintada pelo [tom].
class Selo extends StatelessWidget {
  const Selo(this.texto, {super.key, this.icone, this.tom = Tom.neutro, this.onTap});

  final String texto;
  final IconData? icone;
  final Tom tom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = coresDoTom(context, tom);
    return Material(
      color: c.fundo,
      borderRadius: BorderRadius.circular(kRaioSelo),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRaioSelo),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icone != null) ...[
                Icon(icone, size: 14, color: c.texto),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: c.texto,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão de ação: ícone num quadrado suave e o rótulo embaixo. [ligado] pinta
/// de azul (prova ligada, telas travadas); [tom] perigo para o que desliga.
class BotaoDeAcao extends StatelessWidget {
  const BotaoDeAcao({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.onPressed,
    this.dica,
    this.ligado = false,
    this.tom,
    this.largura = 76,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? onPressed;
  final String? dica;
  final bool ligado;
  final Tom? tom;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final ativo = onPressed != null;
    final doTom = tom == null ? null : coresDoTom(context, tom!);
    final fundo = ligado ? s.primary : (doTom?.fundo ?? s.surfaceContainerHighest);
    final frente = ligado ? s.onPrimary : (doTom?.texto ?? s.onSurface);
    return Semantics(
      container: true,
      button: true,
      enabled: ativo,
      toggled: ligado ? true : null,
      child: Tooltip(
        message: dica ?? rotulo,
        child: InkWell(
          borderRadius: BorderRadius.circular(kRaioBotao),
          onTap: onPressed,
          child: Opacity(
            opacity: ativo ? 1 : 0.4,
            child: SizedBox(
              width: largura,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: fundo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icone, color: frente, size: 24),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      rotulo,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: s.onSurface,
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botões de ação em colunas iguais (4 no celular), quebrando em linhas.
class GradeDeAcoes extends StatelessWidget {
  const GradeDeAcoes({super.key, required this.acoes, this.colunas = 4});

  final List<BotaoDeAcao> acoes;
  final int colunas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricoes) {
        final largura = restricoes.maxWidth / colunas;
        return Wrap(
          children: [
            for (final a in acoes)
              BotaoDeAcao(
                icone: a.icone,
                rotulo: a.rotulo,
                dica: a.dica,
                ligado: a.ligado,
                tom: a.tom,
                onPressed: a.onPressed,
                largura: largura,
              ),
          ],
        );
      },
    );
  }
}

/// Estado do computador para o número da unidade.
enum EstadoDoPc { online, offline, alerta, telao }

/// Número da unidade num quadrado arredondado, pintado pelo estado do
/// computador. Sem número (pareado antes do app 0.13), um ícone.
class SeloDaUnidade extends StatelessWidget {
  const SeloDaUnidade({
    super.key,
    this.numero,
    this.estado = EstadoDoPc.online,
    this.tamanho = 44,
  });

  final int? numero;
  final EstadoDoPc estado;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final tom = switch (estado) {
      EstadoDoPc.online => Tom.primario,
      EstadoDoPc.offline => Tom.neutro,
      EstadoDoPc.alerta => Tom.perigo,
      EstadoDoPc.telao => Tom.atencao,
    };
    final c = coresDoTom(context, tom);
    final icone = switch (estado) {
      EstadoDoPc.telao => Icons.co_present_outlined,
      EstadoDoPc.alerta when numero == null => Icons.warning_amber_rounded,
      _ => Icons.computer_outlined,
    };
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: numero != null && estado != EstadoDoPc.telao
          ? Text(
              '$numero',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: c.texto,
                    fontWeight: FontWeight.w700,
                  ),
            )
          : Icon(icone, color: c.texto, size: 22),
    );
  }
}

/// Estado vazio: ícone, título, texto e uma ação opcional, no centro.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    this.texto,
    this.acao,
  });

  final IconData icone;
  final String titulo;
  final String? texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icone, size: 30, color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(titulo, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
            if (texto != null) ...[
              const SizedBox(height: 6),
              Text(
                texto!,
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ],
            if (acao != null) ...[const SizedBox(height: 20), acao!],
          ],
        ),
      ),
    );
  }
}

/// Confirmação padrão: Cancelar e a ação (vermelha quando [destrutiva]).
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  required String acao,
  bool destrutiva = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final s = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: destrutiva
                ? FilledButton.styleFrom(backgroundColor: s.error, foregroundColor: s.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(acao),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Pede um texto (nome, número…): devolve o texto aparado, ou null se a
/// pessoa cancelou ou deixou vazio.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  String? rotulo,
  String? dica,
  String? ajuda,
  String inicial = '',
  String acao = 'Salvar',
  bool numero = false,
  TextCapitalization capitalizacao = TextCapitalization.sentences,
}) async {
  final texto = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoTexto(
      titulo: titulo,
      rotulo: rotulo,
      dica: dica,
      ajuda: ajuda,
      inicial: inicial,
      acao: acao,
      numero: numero,
      capitalizacao: capitalizacao,
    ),
  );
  final aparado = texto?.trim();
  return aparado == null || aparado.isEmpty ? null : aparado;
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.rotulo,
    required this.dica,
    required this.ajuda,
    required this.inicial,
    required this.acao,
    required this.numero,
    required this.capitalizacao,
  });

  final String titulo;
  final String? rotulo;
  final String? dica;
  final String? ajuda;
  final String inicial;
  final String acao;
  final bool numero;
  final TextCapitalization capitalizacao;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final _ctrl = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: widget.numero ? TextInputType.number : null,
        inputFormatters: widget.numero ? [FilteringTextInputFormatter.digitsOnly] : null,
        textCapitalization: widget.capitalizacao,
        decoration: InputDecoration(
          labelText: widget.rotulo,
          hintText: widget.dica,
          helperText: widget.ajuda,
          helperMaxLines: 3,
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(widget.acao),
        ),
      ],
    );
  }
}
