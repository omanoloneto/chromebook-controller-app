// Comparação "natural" (humana) de strings: trechos de dígitos são comparados
// como NÚMERO, não caractere a caractere. Assim "Unidade 3" < "Unidade 12"
// (e não 12 < 3 como no compareTo puro). Case-insensitive; fora dos dígitos,
// ordena como texto comum. Usado onde a lista mostra unidades numeradas
// (home_sections, class_view) — pura, testável (test/natural_sort_test.dart).

bool _ehDigito(int c) => c >= 0x30 && c <= 0x39; // '0'..'9'

/// Remove zeros à esquerda mantendo ao menos 1 dígito ("007" -> "7", "0" -> "0").
String _semZerosAEsquerda(String s) {
  var i = 0;
  while (i < s.length - 1 && s.codeUnitAt(i) == 0x30) {
    i++;
  }
  return s.substring(i);
}

int compararNatural(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    if (_ehDigito(cx) && _ehDigito(cy)) {
      // Lê o run de dígitos inteiro dos dois lados e compara por magnitude.
      final si = i;
      while (i < x.length && _ehDigito(x.codeUnitAt(i))) {
        i++;
      }
      final sj = j;
      while (j < y.length && _ehDigito(y.codeUnitAt(j))) {
        j++;
      }
      final nx = _semZerosAEsquerda(x.substring(si, i));
      final ny = _semZerosAEsquerda(y.substring(sj, j));
      if (nx.length != ny.length) return nx.length - ny.length; // 9 < 12
      final cmp = nx.compareTo(ny); // mesmo tamanho: lexicográfico = numérico
      if (cmp != 0) return cmp;
    } else {
      if (cx != cy) return cx - cy;
      i++;
      j++;
    }
  }
  // Prefixo igual: a string mais curta vem antes.
  return (x.length - i) - (y.length - j);
}
