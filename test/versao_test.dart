// Versão exibida do PC: prefixo "celita-" some; nome salvo nunca é trocado.

import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/util/versao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versaoCurta', () {
    expect(versaoCurta('celita-0.10.0'), '0.10.0');
    expect(versaoCurta('0.4.11'), '0.4.11');
    expect(versaoCurta(null), isNull);
    expect(versaoCurta(''), isNull);
    expect(versaoCurta('   '), isNull);
    expect(versaoCurta('celita-'), isNull);
  });

  test('nomeComVersao acrescenta a versão sem mexer no nome', () {
    expect(nomeComVersao('Maria (fundo)', 'celita-0.10.0'), 'Maria (fundo) (0.10.0)');
    expect(nomeComVersao('Unidade 3', '0.4.11'), 'Unidade 3 (0.4.11)');
    expect(nomeComVersao('Unidade 3', null), 'Unidade 3');
  });

  test('SessionRegistry.bind preserva a versão já lida', () {
    final reg = SessionRegistry();
    final chave = List<int>.generate(32, (i) => i);
    reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave).versaoExt =
        'celita-0.10.0';
    reg.bind(deviceId: 'pc1', label: 'x', sessionKey: chave); // re-pareamento
    expect(reg.byId('pc1')!.versaoExt, 'celita-0.10.0');
  });
}
