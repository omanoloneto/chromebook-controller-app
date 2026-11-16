// App da monitora: Sala (ajudar o aluno, sair das contas, desligar) e
// Carrinho (bateria e tomada). Sem câmera, fotos, histórico nem bloqueios.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../commands/command.dart';
import '../pairing/monitora_controller.dart';
import 'componentes.dart';
import 'textos_erro.dart';

String textoDaMonitora(String? erro) => switch (erro) {
      'sem_resposta' => kTextoTimeout,
      'sem_internet' => kTextoSemInternet,
      'sem_chave' => 'Este computador ainda não recebeu o acesso das monitoras. '
          'Peça a um professor para abrir o app uma vez.',
      'negado' => 'Seu acesso de monitora foi retirado. Fale com a coordenação.',
      'nao_permitido' => 'Este pedido não é permitido para monitoras.',
      _ => textoErro(erro),
    };

class MonitoraShell extends StatefulWidget {
  const MonitoraShell({super.key, required this.controller, required this.onSair});

  final MonitoraController controller;
  final Future<void> Function() onSair;

  @override
  State<MonitoraShell> createState() => _MonitoraShellState();
}

class _MonitoraShellState extends State<MonitoraShell> {
  int _aba = 0;

  MonitoraController get _c => widget.controller;

  Future<void> _sair() async {
    final ok = await confirmar(
      context,
      titulo: 'Sair do modo monitora',
      mensagem: 'O app volta para a tela inicial. Para entrar de novo, use '
          'Ajustes → Entrar como monitora.',
      acao: 'Sair',
    );
    if (ok) await widget.onSair();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_aba == 0 ? 'Sala' : 'Carrinho'),
          actions: [
            PopupMenuButton<void>(
              itemBuilder: (_) => [
                PopupMenuItem<void>(onTap: _sair, child: const Text('Sair do modo monitora')),
              ],
            ),
          ],
        ),
        body: switch (_c.estado) {
          EstadoMonitora.carregando => const Center(child: CircularProgressIndicator()),
          EstadoMonitora.semAcesso => EstadoVazio(
              icone: Icons.lock_outline,
              titulo: 'Sem acesso de monitora',
              texto: 'Peça à coordenação para liberar seu e-mail em '
                  'Ajustes → Monitoras da escola.',
              acao: FilledButton(onPressed: widget.onSair, child: const Text('Voltar')),
            ),
          EstadoMonitora.pronto => _aba == 0 ? _Sala(controller: _c) : _Carrinho(controller: _c),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.meeting_room_outlined), label: 'Sala'),
            NavigationDestination(icon: Icon(Icons.battery_charging_full), label: 'Carrinho'),
          ],
        ),
      ),
    );
  }
}

void _avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

String _bateria(PcDaMonitora pc) {
  final partes = [
    if (pc.bateria != null) '${pc.bateria}%',
    if (pc.naTomada == true) 'na tomada' else if (pc.naTomada == false) 'fora da tomada',
  ];
  return partes.join(' · ');
}

String _hora(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _LinhaDoPc extends StatelessWidget {
  const _LinhaDoPc({required this.controller, required this.pc, this.detalhe});

  final MonitoraController controller;
  final PcDaMonitora pc;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final ligado = controller.ligado(pc);
    final estado = ligado
        ? (pc.contaAberta == true ? 'Com aluno' : 'Ligado, sem aluno')
        : (pc.lastSeen != null ? 'Desligado desde ${_hora(pc.lastSeen!)}' : 'Desligado');
    final linha = [estado, detalhe ?? _bateria(pc)].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      leading: SeloDaUnidade(
        numero: pc.numero,
        estado: ligado ? EstadoDoPc.online : EstadoDoPc.offline,
      ),
      title: Text(pc.titulo),
      subtitle: Text(linha),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => abrirPcDaMonitora(context, controller, pc),
    );
  }
}

class _Sala extends StatelessWidget {
  const _Sala({required this.controller});

  final MonitoraController controller;

  Future<void> _todos(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    required String acao,
    required String feito,
    required Future<RespostaDoPc> Function(PcDaMonitora) pedido,
    bool destrutiva = false,
  }) async {
    if (!await confirmar(context, titulo: titulo, mensagem: mensagem, acao: acao, destrutiva: destrutiva)) {
      return;
    }
    if (!context.mounted) return;
    final r = await esperarComSpinner(context, 'Enviando…', controller.paraTodosLigados(pedido));
    if (!context.mounted) return;
    _avisar(context, r.total == 0 ? 'Nenhum computador ligado.' : '$feito em ${r.ok} de ${r.total}.');
  }

  @override
  Widget build(BuildContext context) {
    final pcs = controller.pcs;
    final ligados = pcs.where(controller.ligado).toList();
    final comAluno = ligados.where((p) => p.contaAberta == true).length;
    if (pcs.isEmpty) {
      return const EstadoVazio(
        icone: Icons.computer_outlined,
        titulo: 'Nenhum computador na escola',
        texto: 'Os computadores aparecem aqui quando um professor os conecta.',
      );
    }
    return ListView(
      padding: recuoDaLista(context),
      children: [
        TituloDeSecao('${ligados.length} de ${pcs.length} ligados · $comAluno com aluno'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GradeDeAcoes(
            colunas: 3,
            acoes: [
              BotaoDeAcao(
                icone: Icons.tab_unselected,
                rotulo: 'Fechar abas',
                onPressed: ligados.isEmpty
                    ? null
                    : () => _todos(
                          context,
                          titulo: 'Fechar as abas de todos',
                          mensagem: 'Fecha os sites abertos em todos os computadores ligados.',
                          acao: 'Fechar',
                          feito: 'Abas fechadas',
                          pedido: controller.fecharAbas,
                        ),
              ),
              BotaoDeAcao(
                icone: Icons.logout,
                rotulo: 'Sair das contas',
                onPressed: ligados.isEmpty
                    ? null
                    : () => _todos(
                          context,
                          titulo: 'Sair das contas',
                          mensagem: 'Encerra a sessão dos alunos em todos os computadores '
                              'ligados. O que não foi salvo se perde.',
                          acao: 'Sair das contas',
                          feito: 'Contas encerradas',
                          pedido: (pc) => controller.energia(pc, AcaoEnergia.encerrar),
                          destrutiva: true,
                        ),
              ),
              BotaoDeAcao(
                icone: Icons.power_settings_new,
                rotulo: 'Desligar todos',
                tom: Tom.perigo,
                onPressed: ligados.isEmpty
                    ? null
                    : () => _todos(
                          context,
                          titulo: 'Desligar todos',
                          mensagem: 'Desliga todos os computadores ligados. O que não foi '
                              'salvo se perde.',
                          acao: 'Desligar',
                          feito: 'Desligando',
                          pedido: (pc) => controller.energia(pc, AcaoEnergia.desligar),
                          destrutiva: true,
                        ),
              ),
            ],
          ),
        ),
        const TituloDeSecao('Computadores'),
        for (final pc in pcs) _LinhaDoPc(controller: controller, pc: pc),
      ],
    );
  }
}

class _Carrinho extends StatelessWidget {
  const _Carrinho({required this.controller});

  final MonitoraController controller;

  @override
  Widget build(BuildContext context) {
    final pcs = controller.pcs;
    final fora = pcs.where((p) => p.naTomada == false).toList()
      ..sort((a, b) => (a.bateria ?? 101).compareTo(b.bateria ?? 101));
    final naTomada = pcs.where((p) => p.naTomada == true).toList();
    final semNoticia = pcs.where((p) => p.naTomada == null).toList();
    final ligados = pcs.where(controller.ligado).length;
    final baixa = fora.where((p) => (p.bateria ?? 100) < kBateriaBaixa).length;
    if (pcs.isEmpty) {
      return const EstadoVazio(icone: Icons.battery_unknown_outlined, titulo: 'Nenhum computador na escola');
    }
    return ListView(
      padding: recuoDaLista(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Selo('${naTomada.length} de ${pcs.length} na tomada', icone: Icons.power, tom: Tom.primario),
              if (baixa > 0) Selo('$baixa com bateria baixa', icone: Icons.battery_alert, tom: Tom.perigo),
              if (ligados > 0) Selo('$ligados ainda ligados', icone: Icons.computer, tom: Tom.atencao),
            ],
          ),
        ),
        if (fora.isNotEmpty) ...[
          const TituloDeSecao('Fora da tomada'),
          for (final pc in fora) _LinhaDoPc(controller: controller, pc: pc),
        ],
        if (semNoticia.isNotEmpty) ...[
          const TituloDeSecao('Sem notícia da bateria'),
          for (final pc in semNoticia)
            _LinhaDoPc(controller: controller, pc: pc, detalhe: 'ligue para atualizar'),
        ],
        if (naTomada.isNotEmpty) ...[
          const TituloDeSecao('Na tomada'),
          for (final pc in naTomada) _LinhaDoPc(controller: controller, pc: pc),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'A bateria é a última que o computador enviou: com ele desligado, '
            'vale a hora em que desligou.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

Future<void> abrirPcDaMonitora(BuildContext context, MonitoraController c, PcDaMonitora pc) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: c,
        builder: (sheet, _) {
          final ligado = c.ligado(pc);
          final comAluno = pc.contaAberta == true;
          Future<void> pedir(
            String espera,
            String feito,
            Future<RespostaDoPc> Function() pedido,
          ) async {
            final r = await esperarComSpinner(sheet, espera, pedido());
            if (!sheet.mounted) return;
            _avisar(sheet, r.ok ? feito : textoDaMonitora(r.erro));
          }

          Future<void> energia(AcaoEnergia acao, String titulo, String mensagem, String feito) async {
            if (!await confirmar(sheet, titulo: titulo, mensagem: mensagem, acao: titulo, destrutiva: true)) {
              return;
            }
            if (!sheet.mounted) return;
            await pedir('Enviando…', feito, () => c.energia(pc, acao));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: SeloDaUnidade(numero: pc.numero, estado: ligado ? EstadoDoPc.online : EstadoDoPc.offline),
                    title: Text(pc.titulo),
                    subtitle: Text(ligado ? (comAluno ? 'Com aluno' : 'Ligado, sem aluno') : 'Desligado'),
                  ),
                  GradeDeAcoes(
                    colunas: 3,
                    acoes: [
                      BotaoDeAcao(
                        icone: Icons.desktop_windows_outlined,
                        rotulo: 'Ver tela',
                        onPressed: ligado
                            ? () => Navigator.of(sheet).push(
                                  MaterialPageRoute<void>(builder: (_) => _TelaDoPc(controller: c, pc: pc)),
                                )
                            : null,
                      ),
                      BotaoDeAcao(
                        icone: Icons.chat_bubble_outline,
                        rotulo: 'Mensagem',
                        onPressed: ligado
                            ? () async {
                                final texto = await pedirTexto(
                                  sheet,
                                  titulo: 'Mensagem para ${pc.titulo}',
                                  rotulo: 'Mensagem',
                                  acao: 'Enviar',
                                );
                                if (texto == null || !sheet.mounted) return;
                                await pedir('Enviando…', 'Mensagem entregue.', () => c.mensagem(pc, texto));
                              }
                            : null,
                      ),
                      BotaoDeAcao(
                        icone: Icons.tab_unselected,
                        rotulo: 'Fechar abas',
                        onPressed: ligado
                            ? () => pedir('Fechando…', 'Abas fechadas.', () => c.fecharAbas(pc))
                            : null,
                      ),
                      BotaoDeAcao(
                        icone: Icons.logout,
                        rotulo: 'Sair da conta',
                        onPressed: ligado
                            ? () => energia(
                                  AcaoEnergia.encerrar,
                                  'Sair da conta',
                                  'Encerra a sessão do aluno neste computador. O que não foi salvo se perde.',
                                  'Conta encerrada.',
                                )
                            : null,
                      ),
                      BotaoDeAcao(
                        icone: Icons.restart_alt,
                        rotulo: 'Reiniciar',
                        onPressed: ligado
                            ? () => energia(
                                  AcaoEnergia.reiniciar,
                                  'Reiniciar',
                                  'Reinicia este computador. O que não foi salvo se perde.',
                                  'Reiniciando.',
                                )
                            : null,
                      ),
                      BotaoDeAcao(
                        icone: Icons.power_settings_new,
                        rotulo: 'Desligar',
                        tom: Tom.perigo,
                        onPressed: ligado
                            ? () => energia(
                                  AcaoEnergia.desligar,
                                  'Desligar',
                                  'Desliga este computador. O que não foi salvo se perde.',
                                  'Desligando.',
                                )
                            : null,
                      ),
                    ],
                  ),
                  if (!ligado)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text('Ligue o computador pelo botão para usar estas ações.'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

class _TelaDoPc extends StatefulWidget {
  const _TelaDoPc({required this.controller, required this.pc});

  final MonitoraController controller;
  final PcDaMonitora pc;

  @override
  State<_TelaDoPc> createState() => _TelaDoPcState();
}

class _TelaDoPcState extends State<_TelaDoPc> {
  Uint8List? _jpeg;
  String? _erro;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    final r = await widget.controller.verTela(widget.pc);
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _jpeg = r.jpeg ?? _jpeg;
      _erro = r.jpeg == null ? textoDaMonitora(r.erro) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tela da ${widget.pc.titulo}'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _buscando ? null : _buscar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_buscando) const LinearProgressIndicator(),
          if (_erro != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)),
          Expanded(
            child: _jpeg == null
                ? const SizedBox.shrink()
                : InteractiveViewer(child: Center(child: Image.memory(_jpeg!, gaplessPlayback: true))),
          ),
        ],
      ),
    );
  }
}
