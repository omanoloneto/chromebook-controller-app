// Modo prova (item 25): ligar e desligar em 1 toque, com os avisos antes de
// ligar (lista vazia; computadores com versão antiga) e a lista de "Sites
// permitidos na prova" da aba Sites. Ver SPEC-turma §8.4 e §8.5.

import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import '../util/versao.dart';

/// Linha de ajuda da lista (limites declarados do modo prova).
const String kAjudaProva =
    'Vale para o navegador. Apps Android do Chromebook e páginas dentro de '
    'outras páginas não são bloqueados.';

/// Toque no botão "Prova" (ligar) ou "Prova ligada" (desligar).
/// [onEditarSites] leva à lista de sites permitidos (aba Sites).
Future<void> alternarProva(
  BuildContext context,
  PairingController pairing, {
  required VoidCallback onEditarSites,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String texto, {SnackBarAction? acao}) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      // Com ação o SnackBar ficaria parado na tela (padrão do Flutter):
      // aqui ele sai sozinho em 4 s, como os outros.
      SnackBar(content: Text(texto), action: acao, persist: false),
    );

  Future<void> ligar() async {
    final erro = await pairing.ligarProva();
    snack(
      erro ?? 'Modo prova ligado: só os sites permitidos abrem.',
      acao: erro != null
          ? null
          : SnackBarAction(label: 'Editar sites', onPressed: onEditarSites),
    );
  }

  if (pairing.provaLigada) {
    final erro = await pairing.desligarProva();
    snack(
      erro ?? 'Modo prova desligado.',
      acao: erro != null
          ? null
          : SnackBarAction(label: 'Desfazer', onPressed: ligar),
    );
    return;
  }

  final sem = pairing.motivoSemTurma;
  if (sem != null) {
    snack(sem);
    return;
  }
  if (pairing.sitesProva.isEmpty) {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fact_check_outlined),
        title: const Text('Lista de sites vazia'),
        content: const Text(
          'A lista de sites permitidos está vazia. Com o modo prova ligado, '
          'só a página inicial da escola abre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'editar'),
            child: const Text('Editar lista'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'ligar'),
            child: const Text('Ligar mesmo assim'),
          ),
        ],
      ),
    );
    if (r == 'editar') onEditarSites();
    if (r != 'ligar' || !context.mounted) return;
  }
  final antigos = pairing.pcsSemModoProva;
  if (antigos.isNotEmpty) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogoVersaoAntigaProva(pairing: pairing),
    );
    if (ok != true || !context.mounted) return;
  }
  await ligar();
}

/// "Alguns computadores não vão entrar em modo prova": lista os PCs com
/// versão antiga, oferece "Atualizar agora" para os do Celita OS e explica que
/// os Chromebooks se atualizam sozinhos. true = "Ligar mesmo assim".
class DialogoVersaoAntigaProva extends StatefulWidget {
  const DialogoVersaoAntigaProva({super.key, required this.pairing});

  final PairingController pairing;

  @override
  State<DialogoVersaoAntigaProva> createState() =>
      _DialogoVersaoAntigaProvaState();
}

class _DialogoVersaoAntigaProvaState extends State<DialogoVersaoAntigaProva> {
  // null = ainda não pediu; senão quantos aceitaram o pedido.
  int? _atualizando;

  // Pedido em andamento: o toque duplo não manda `atualizar` duas vezes.
  bool _pedindo = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.pairing;
    final antigos = p.pcsSemModoProva;
    final nomes = [for (final s in antigos) p.nomeDoPc(s.deviceId)];
    final celita = [
      for (final s in antigos)
        if (temCelita(s.versaoExt)) s,
    ];
    final chromebooks = antigos.length - celita.length;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Alguns computadores não vão entrar em modo prova'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estes computadores têm uma versão antiga e continuariam com '
              'todos os sites liberados: ${nomes.join(', ')}.',
            ),
            if (celita.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (_atualizando == null)
                OutlinedButton.icon(
                  onPressed: _pedindo
                      ? null
                      : () async {
                          setState(() => _pedindo = true);
                          var n = 0;
                          for (final s in celita) {
                            if (await p.atualizarPc(s.deviceId) == null) n++;
                          }
                          if (mounted) setState(() => _atualizando = n);
                        },
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Atualizar agora'),
                )
              else
                Text(
                  _atualizando == 0
                      ? 'Não deu para pedir a atualização agora. Confira se os computadores com Celita OS estão ligados.'
                      : _atualizando == 1
                          ? 'Pedido enviado: 1 computador vai se atualizar sozinho.'
                          : 'Pedido enviado: $_atualizando computadores vão se atualizar sozinhos.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
            ],
            if (chromebooks > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Os Chromebooks se atualizam sozinhos em algumas horas.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ligar mesmo assim'),
        ),
      ],
    );
  }
}

// ---- Aba Sites: "Sites permitidos na prova" ----------------------------------------

/// Lista de sites permitidos na prova (store da escola `prova`). Mesmo padrão
/// visual e mesma normalização das regras; editar com a prova ligada vale na
/// hora para os computadores da prova.
class ProvaSitesView extends StatelessWidget {
  const ProvaSitesView({super.key, required this.pairing});

  final PairingController pairing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sites = pairing.sitesProva;
    final estiloAjuda = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Sites permitidos na prova',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: scheme.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Com o modo prova ligado, só estes sites e a página inicial da '
            'escola abrem nos computadores da aula.',
            style: estiloAjuda,
          ),
        ),
        if (pairing.provaLigada)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.fact_check, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'O modo prova está ligado: as mudanças valem na hora.',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => dialogoSitesProvaEmLote(context, pairing),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Colar vários sites'),
            ),
          ),
        ),
        const Divider(height: 1),
        if (sites.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Nenhum site na lista ainda. Toque em "Novo site" aqui embaixo '
              'para começar (ex.: khanacademy.org).',
            ),
          ),
        for (var i = 0; i < sites.length; i++) ...[
          Dismissible(
            key: ValueKey('prova|${sites[i]}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: scheme.error,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.delete, color: scheme.onError),
            ),
            onDismissed: (_) => _remover(pairing, sites[i]),
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: scheme.primary),
              title: Text(sites[i]),
              trailing: IconButton(
                tooltip: 'Tirar da lista',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remover(pairing, sites[i]),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Domínio (khanacademy.org) vale para subdomínios '
            '(pt.khanacademy.org). Com "/" vira prefixo '
            '(youtube.com/@canal).\n$kAjudaProva',
            style: estiloAjuda,
          ),
        ),
      ],
    );
  }
}

// Tira pelo nome, não pela posição: a lista pode ter mudado (outro professor
// da escola editou) entre desenhar a linha e o toque.
void _remover(PairingController pairing, String site) {
  final i = pairing.sitesProva.indexOf(site);
  if (i >= 0) pairing.removerSiteProva(i);
}

/// "Novo site" da lista da prova.
Future<void> dialogoNovoSiteProva(
  BuildContext context,
  PairingController pairing,
) async {
  final ctrl = TextEditingController();
  final texto = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Novo site permitido'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Domínio ou prefixo',
          hintText: 'ex.: khanacademy.org',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Adicionar'),
        ),
      ],
    ),
  );
  if (texto == null || texto.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await pairing.adicionarSiteProva(texto);
  if (!ok) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Não deu para adicionar: o site já está na lista, o endereço não '
            'é válido ou é amplo demais (como "com.br").',
          ),
        ),
      );
  }
}

/// "Colar vários sites": um por linha (ou separados por vírgula/espaço).
Future<void> dialogoSitesProvaEmLote(
  BuildContext context,
  PairingController pairing,
) async {
  final ctrl = TextEditingController();
  final texto = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Colar vários sites'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        autocorrect: false,
        minLines: 4,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          hintText: 'khanacademy.org\nwikipedia.org\ngoogle.com/maps',
          helperText: 'Um site por linha.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Adicionar'),
        ),
      ],
    ),
  );
  if (texto == null || texto.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final n = await pairing.adicionarSitesProvaEmLote(texto);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'Nenhum site novo: já estavam na lista ou não são válidos.'
              : n == 1
                  ? '1 site adicionado.'
                  : '$n sites adicionados.',
        ),
      ),
    );
}
