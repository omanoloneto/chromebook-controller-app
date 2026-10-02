// Canal up/ (aluno -> professor): quem lê, quem apaga e o que aparece em
// Recados. Puro (sem Firebase) — igual ao teacher/up_router.py do desktop e
// testável em test/up_router_test.dart. Ver SPEC-turma §2.4–§2.7.

import 'dart:collection';

import '../commands/command.dart';

/// O que fazer com o `up` de um PC, pela reserva de aula (multi-professor).
enum DestinoUp {
  /// PC reservado por OUTRO professor: nem decifra, nem apaga.
  ignorar,

  /// PC livre na escola: aparece em Recados de todo MEMBRO, sem notificação.
  mostrar,

  /// Sem escola, ou PC reservado por mim: aparece e toca o celular.
  mostrarENotificar,
}

DestinoUp destinoDoUp({
  required bool modoEscola,
  required bool reservadoPorOutro,
  required bool reservadoPorMim,
}) {
  if (!modoEscola) return DestinoUp.mostrarENotificar;
  if (reservadoPorOutro) return DestinoUp.ignorar;
  if (reservadoPorMim) return DestinoUp.mostrarENotificar;
  return DestinoUp.mostrar;
}

const String _alfabetoPushId =
    '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// Milissegundos (relógio do servidor) codificados nos 8 primeiros caracteres
/// de um push id do Firebase; null = não é push id.
int? pushIdMs(String key) {
  if (key.length < 8) return null;
  var ms = 0;
  for (var i = 0; i < 8; i++) {
    final v = _alfabetoPushId.indexOf(key[i]);
    if (v < 0) return null;
    ms = ms * 64 + v;
  }
  return ms;
}

/// Resposta de [UpRouter.aoChegar]: decifrar ou não o item novo, e quais
/// chaves apagar sem ler (velhas demais ou além do teto de 20 por PC).
class ChegadaUp {
  const ChegadaUp({
    required this.ler,
    this.apagar = const [],
    this.silenciou = false,
  });

  final bool ler;
  final List<String> apagar;

  /// O PC acabou de passar do limite e ficou silenciado por 10 min (o
  /// controller põe a linha "Muitas mensagens deste computador…" em Recados).
  final bool silenciou;
}

/// Estado do canal up/ por PC: teto de pendentes, silêncio por excesso,
/// apagar o que passou de 12 h e deduplicar por (deviceId, mid).
class UpRouter {
  UpRouter({
    this.maxPendentes = kUpMaxEntradas,
    this.limiteSilencio = 20,
    this.janelaSilencio = const Duration(minutes: 10),
    this.duracaoSilencio = const Duration(minutes: 10),
    this.idadeMax = kUpIdadeMaxProfessor,
  });

  final int maxPendentes;
  final int limiteSilencio;
  final Duration janelaSilencio;
  final Duration duracaoSilencio;
  final Duration idadeMax;

  // Chaves presentes em up/ por PC (ordem do push id = ordem de chegada).
  final Map<String, SplayTreeSet<String>> _chaves = {};
  // Dedup: deviceId -> mid -> chaves com aquele mid (o PC pode reenviar).
  final Map<String, Map<String, Set<String>>> _porMid = {};
  final Map<String, Map<String, String>> _midDaChave = {};
  // Push ids (ms) dos itens novos de cada PC, para o silêncio.
  final Map<String, List<int>> _chegadas = {};
  final Map<String, int> _silenciadoAte = {};

  /// Silenciado até (ms do servidor), ou null.
  int? silenciadoAte(String deviceId, int agoraMs) {
    final ate = _silenciadoAte[deviceId];
    if (ate == null || agoraMs >= ate) return null;
    return ate;
  }

  /// Uma chave nova apareceu em up/ (antes de decifrar). [agoraMs] = relógio
  /// do servidor. Só deve ser chamado para PCs cujo destino não é ignorar.
  ChegadaUp aoChegar(String deviceId, String key, int agoraMs) {
    final ms = pushIdMs(key);
    if (ms == null) return const ChegadaUp(ler: false); // não é do protocolo
    if (ms < agoraMs - idadeMax.inMilliseconds) {
      return ChegadaUp(ler: false, apagar: [key]); // PC morto: qualquer um apaga
    }
    final chaves = _chaves.putIfAbsent(deviceId, SplayTreeSet<String>.new);
    chaves.add(key);
    final apagar = <String>[];
    while (chaves.length > maxPendentes) {
      final velha = chaves.first;
      chaves.remove(velha);
      // O mid continua ligado à chave até o `onChildRemoved` dela: é ele que
      // tira de Recados o pedido/mão que já tinha sido lido.
      apagar.add(velha);
    }
    final ler = chaves.contains(key);

    // Silêncio: mais de [limiteSilencio] itens novos em [janelaSilencio].
    var silenciou = false;
    final corte = agoraMs - janelaSilencio.inMilliseconds;
    if (ms >= corte) {
      final lista = _chegadas.putIfAbsent(deviceId, () => [])
        ..add(ms)
        ..removeWhere((t) => t < corte);
      if (lista.length > limiteSilencio && silenciadoAte(deviceId, agoraMs) == null) {
        _silenciadoAte[deviceId] = agoraMs + duracaoSilencio.inMilliseconds;
        silenciou = true;
      }
    }
    if (silenciadoAte(deviceId, agoraMs) != null) {
      return ChegadaUp(ler: false, apagar: apagar, silenciou: silenciou);
    }
    return ChegadaUp(ler: ler, apagar: apagar);
  }

  /// Item decifrado e validado. false = repetido (mesmo mid deste PC já
  /// entregue): não mostra de novo, mas a chave fica ligada ao mid para ser
  /// apagada junto quando o professor agir.
  bool aoLer(String deviceId, String key, UpMessage msg) {
    final porMid = _porMid.putIfAbsent(deviceId, () => {});
    final ja = porMid.containsKey(msg.mid);
    porMid.putIfAbsent(msg.mid, () => <String>{}).add(key);
    _midDaChave.putIfAbsent(deviceId, () => {})[key] = msg.mid;
    return !ja;
  }

  /// A chave sumiu de up/ (alguém agiu, o PC podou). Devolve o mid quando foi
  /// a última chave dele — o item sai de Recados.
  String? aoRemover(String deviceId, String key) {
    _chaves[deviceId]?.remove(key);
    return _esquecerChave(deviceId, key);
  }

  /// Chaves a apagar quando o professor age sobre o item [mid].
  List<String> chavesDe(String deviceId, String mid) =>
      List.of(_porMid[deviceId]?[mid] ?? const <String>{});

  /// Esquece tudo de um PC (desvinculado, aula encerrada).
  void limparPc(String deviceId) {
    _chaves.remove(deviceId);
    _porMid.remove(deviceId);
    _midDaChave.remove(deviceId);
    _chegadas.remove(deviceId);
    _silenciadoAte.remove(deviceId);
  }

  String? _esquecerChave(String deviceId, String key) {
    final mid = _midDaChave[deviceId]?.remove(key);
    if (mid == null) return null;
    final chaves = _porMid[deviceId]?[mid];
    chaves?.remove(key);
    if (chaves == null || chaves.isEmpty) {
      _porMid[deviceId]?.remove(mid);
      return mid;
    }
    return null;
  }
}
