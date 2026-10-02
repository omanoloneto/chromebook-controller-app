// Conversa com o aluno de um PC (item 29) e "Mensagem para a turma". Bolhas
// estilo mensageiro: professor à direita, aluno à esquerda, a situação de
// cada mensagem do professor embaixo dela ("✓ Entregue", "Aguardando (PC
// desligado)"…). Abrir a conversa zera as não lidas e baixa a mão. Texto que
// vem da rede é sempre texto puro (Text), nunca markup nem link.
// Ver SPEC-turma §3.6.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/conversa.dart';
import '../commands/command.dart';
import '../pairing/pairing_controller.dart';
import '../util/versao.dart';
import 'theme.dart';

/// Nome de rota da conversa de um PC: o toque numa notificação volta a ela em
/// vez de empilhar outra igual.
String rotaDaConversa(String deviceId) => '/conversa/$deviceId';

Route<void> rotaChatPage(PairingController pairing, String deviceId) =>
    MaterialPageRoute(
      settings: RouteSettings(name: rotaDaConversa(deviceId)),
      builder: (_) => ChatPage(pairing: pairing, deviceId: deviceId),
    );

/// Abre a conversa do PC (sem empilhar outra igual em cima dela).
void abrirConversa(
  BuildContext context,
  PairingController pairing,
  String deviceId,
) {
  final nav = Navigator.of(context);
  var jaNoTopo = false;
  nav.popUntil((r) {
    jaNoTopo = r.settings.name == rotaDaConversa(deviceId);
    return true;
  });
  if (jaNoTopo) return;
  nav.push(rotaChatPage(pairing, deviceId));
}

/// Iniciais para o avatar: "Ana Paula Souza" → "AS"; "Pedro" → "PE";
/// "Unidade 12" → "U1". Vazio → "?".
String iniciaisDe(String nome) {
  final palavras =
      nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (palavras.isEmpty) return '?';
  String primeira(String p) => String.fromCharCodes(p.runes.take(1));
  if (palavras.length == 1) {
    return String.fromCharCodes(palavras.first.runes.take(2)).toUpperCase();
  }
  return (primeira(palavras.first) + primeira(palavras.last)).toUpperCase();
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.pairing, required this.deviceId});

  final PairingController pairing;
  final String deviceId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  PairingController get _p => widget.pairing;
  String get _id => widget.deviceId;

  final _ctrl = TextEditingController();
  final _foco = FocusNode();
  bool _enviando = false;
  bool _appNaFrente = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final estado = WidgetsBinding.instance.lifecycleState;
    _appNaFrente = estado == null || estado == AppLifecycleState.resumed;
    _p.addListener(_onChange);
    _ctrl.addListener(() => setState(() {}));
    // Abrir zera as não lidas e baixa a mão (apaga o raise_hand do up/).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_p.abrirConversa(_id));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _p.removeListener(_onChange);
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appNaFrente = state == AppLifecycleState.resumed;
    if (_appNaFrente) _marcarLida();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _marcarLida();
  }

  // Mensagem que chega com a conversa aberta (e o app na frente) já é lida.
  void _marcarLida() {
    if (!_appNaFrente || _p.naoLidasDe(_id) == 0) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    scheduleMicrotask(() {
      if (mounted) _p.marcarConversaLida(_id);
    });
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text;
    if (texto.trim().isEmpty || _enviando) return;
    final antes = _p.conversaDe(_id);
    final ultimoAntes = antes.isEmpty ? null : antes.last;
    setState(() => _enviando = true);
    final erro = await _p.enviarChat(_id, texto);
    if (!mounted) return;
    final depois = _p.conversaDe(_id);
    // O balão entrou na conversa (mesmo que a escrita tenha falhado, ele
    // mostra a falha): o campo esvazia. Recusado antes disso: o texto fica.
    final entrou = depois.isNotEmpty && !identical(depois.last, ultimoAntes);
    setState(() => _enviando = false);
    if (erro == null || entrou) _ctrl.clear();
    if (erro != null) _snack(erro);
  }

  @override
  Widget build(BuildContext context) {
    final s = _p.pcPorId(_id);
    if (s == null && _p.carregandoPc(_id)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PC desconectado')),
        body: const Center(child: Text('Este PC não está mais conectado.')),
      );
    }
    final nome = _p.nomeDoPc(_id);
    final on = _p.isOnline(s);
    final aluno = _p.alunoDe(_id);
    final scheme = Theme.of(context).colorScheme;
    final antigo = !suportaTurma(s.versaoExt);
    final professor = _p.professorQueTravou(_id);
    final itens = _p.conversaDe(_id);
    final legendaPc = [
      if (aluno != null) _p.nomeDe(s),
      on ? 'online' : 'desligado — recebe quando ligar',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                iniciaisDe(nome),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color:
                            on ? cores(context).online : cores(context).offline,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          legendaPc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (professor == null && _p.maoLevantada(_id))
            _linhaDaMao(nome, s.maoEm),
          if (antigo)
            _aviso(
              Icons.info_outline,
              'Este computador tem uma versão antiga: o aluno vê suas '
              'mensagens, mas não consegue responder.',
            ),
          Expanded(
            child: itens.isEmpty
                ? _vazio(nome, antigo)
                : _lista(itens, s.versaoExt),
          ),
          const Divider(height: 0.5),
          professor != null
              ? _aviso(
                  Icons.lock_outline,
                  'Este computador está na aula de $professor.',
                )
              : _campo(),
        ],
      ),
    );
  }

  Widget _linhaDaMao(String nome, int? em) {
    final c = cores(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: c.atencao.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.back_hand, size: 20, color: c.atencao),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                em == null
                    ? '$nome levantou a mão'
                    : '$nome levantou a mão às ${horaMinuto(em)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _p.baixarMao(_id),
              child: const Text('Baixar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aviso(IconData icone, String texto) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icone, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                texto,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vazio(String nome, bool antigo) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Nenhuma mensagem ainda.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              antigo
                  ? 'Escreva para $nome. A mensagem aparece na tela do computador.'
                  : 'Escreva para $nome. A conversa abre num cantinho da tela '
                      'do computador, e o aluno pode responder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista(List<ChatItem> itens, String? ext) {
    // Lista invertida: a mensagem mais nova fica embaixo, perto do campo, e
    // a tela acompanha quem chega sem precisar rolar.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: itens.length,
      itemBuilder: (context, i) {
        final idx = itens.length - 1 - i;
        final item = itens[idx];
        final anterior = idx > 0 ? itens[idx - 1] : null;
        final proximo = idx < itens.length - 1 ? itens[idx + 1] : null;
        bool mesmoGrupo(ChatItem? a, ChatItem? b) =>
            a != null &&
            b != null &&
            a.autor == b.autor &&
            (a.ts - b.ts).abs() < const Duration(minutes: 2).inMilliseconds;
        return BolhaDoChat(
          item: item,
          legenda: item.autor == AutorChat.professor
              ? legendaDoBalao(item, ext: ext)
              : '',
          inicioDoGrupo: !mesmoGrupo(item, anterior),
          fimDoGrupo: !mesmoGrupo(item, proximo),
        );
      },
    );
  }

  Widget _campo() {
    final scheme = Theme.of(context).colorScheme;
    final temTexto = _ctrl.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _foco,
                minLines: 1,
                maxLines: 5,
                maxLength: kMaxChatTexto,
                // O contador só aparece perto do limite.
                buildCounter: (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) =>
                    maxLength != null && currentLength > maxLength - 50
                        ? Text('$currentLength/$maxLength')
                        : null,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: 'Escreva uma mensagem…',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: scheme.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton.filled(
                tooltip: 'Enviar',
                onPressed: temTexto && !_enviando ? _enviar : null,
                icon: _enviando
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma bolha da conversa. Professor à direita (primaryContainer), aluno à
/// esquerda (surfaceContainerHighest), linha de sistema centralizada. Embaixo:
/// a hora e, no professor, a situação da entrega.
class BolhaDoChat extends StatelessWidget {
  const BolhaDoChat({
    super.key,
    required this.item,
    required this.legenda,
    this.inicioDoGrupo = true,
    this.fimDoGrupo = true,
  });

  final ChatItem item;

  /// Legenda do professor ("✓ Entregue · para a turma"); vazia no aluno.
  final String legenda;
  final bool inicioDoGrupo;
  final bool fimDoGrupo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    if (item.autor == AutorChat.sistema) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            item.texto,
            textAlign: TextAlign.center,
            style: texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final meu = item.autor == AutorChat.professor;
    final fundo =
        meu ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final frente = meu ? scheme.onPrimaryContainer : scheme.onSurface;
    const r = Radius.circular(18);
    const canto = Radius.circular(4);
    // Bolhas seguidas do mesmo autor se encostam pelo lado dele.
    final raio = BorderRadius.only(
      topLeft: !meu && !inicioDoGrupo ? canto : r,
      bottomLeft: !meu && !fimDoGrupo ? canto : r,
      topRight: meu && !inicioDoGrupo ? canto : r,
      bottomRight: meu && !fimDoGrupo ? canto : r,
    );
    final problema = switch (item.estado) {
      EstadoBalao.erro ||
      EstadoBalao.ninguemLogado ||
      EstadoBalao.semResposta =>
        true,
      _ => false,
    };
    final corLegenda = problema ? scheme.error : scheme.onSurfaceVariant;
    final rodape =
        [horaMinuto(item.ts), if (legenda.isNotEmpty) legenda].join(' · ');

    return Padding(
      padding: EdgeInsets.only(top: inicioDoGrupo ? 10 : 2),
      child: Column(
        crossAxisAlignment:
            meu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: fundo, borderRadius: raio),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                // Texto da rede: Text puro (nada vira markup ou link).
                child: Text(
                  item.texto,
                  style: texto.bodyLarge?.copyWith(color: frente, height: 1.3),
                ),
              ),
            ),
          ),
          // Hora no fim do grupo; a situação de cada mensagem do professor
          // aparece sempre que não for "✓ Entregue".
          if (fimDoGrupo || (meu && item.estado != EstadoBalao.entregue))
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.estado == EstadoBalao.enviando ||
                      item.estado == EstadoBalao.aguardando)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.schedule, size: 12, color: corLegenda),
                    ),
                  Flexible(
                    child: Text(
                      rodape,
                      style: texto.labelSmall?.copyWith(color: corLegenda),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- Mensagem para a turma ---------------------------------------------------------

/// Sheet "Mensagem para a turma": um chat para cada aluno da aula (cada um
/// responde na própria conversa). A faixa da aba Aula acompanha a entrega.
Future<void> mostrarSheetMensagemTurma(
  BuildContext context,
  PairingController pairing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final sem = pairing.motivoSemTurma;
  if (sem != null) {
    snack(sem);
    return;
  }
  final n = pairing.pcsDaTurma.length;
  final ctrl = TextEditingController();
  final texto = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mensagem para a turma',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Chega na conversa de cada aluno, e cada um pode responder.',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: kMaxChatTexto,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setSheet(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Ex.: Abram a página 12 do livro.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: ctrl.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(ctx, ctrl.text),
                  icon: const Icon(Icons.send),
                  label: Text(
                    n == 1 ? 'Enviar para 1 aluno' : 'Enviar para $n alunos',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (texto == null) return;
  final erro = await pairing.enviarMensagemParaTurma(texto);
  if (erro != null) snack(erro);
}
