// Ids de comando e de mensagem (`mid`): 12 bytes aleatórios em base64url, 16
// caracteres. Substitui o antigo 'a'+contador, que se repetia entre
// professores e entre reinícios do app. Para o PC o id é opaco: ele só o
// devolve no ack e em `aplicado.acks`. Ver docs/protocolo.md §3 ("Ids").

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

final Random _aleatorio = Random.secure();

/// 12 bytes aleatórios em base64url sem `=` (16 caracteres).
String novoId() {
  final bytes = List<int>.generate(12, (_) => _aleatorio.nextInt(256));
  return base64Url.encode(bytes); // 12 bytes = 16 chars, sem padding
}

/// Formato de [novoId] (e de qualquer id de 16 chars base64url).
final RegExp formatoDeId = RegExp(r'^[A-Za-z0-9_-]{16}$');

/// Ids que ESTE processo emitiu ("pertence a mim"), limitado aos últimos
/// [limite]. Cliente novo só apaga ack de id seu: os acks de outro professor
/// ficam para ele (e o PC poda o resto).
class IdsEmitidos {
  IdsEmitidos({this.limite = 500});

  final int limite;
  final LinkedHashSet<String> _ids = LinkedHashSet<String>();

  void registrar(String id) {
    _ids.remove(id);
    _ids.add(id);
    while (_ids.length > limite) {
      _ids.remove(_ids.first);
    }
  }

  bool contem(String id) => _ids.contains(id);

  int get length => _ids.length;
}
