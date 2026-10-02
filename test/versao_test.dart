// Versão exibida do PC: prefixo "celita-" some; nome salvo nunca é trocado.

import 'package:controle_de_aula/src/cloud/session_registry.dart';
import 'package:controle_de_aula/src/cloud/versao_publicada.dart';
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

  test('nomeComVersao mostra a versão do Celita OS e marca desatualizado', () {
    expect(nomeComVersao('Maria (fundo)', '1.23.0'), 'Maria (fundo) (1.23.0)');
    expect(nomeComVersao('Unidade 3', '1.22.0', desatualizado: true),
        'Unidade 3 (1.22.0 · desatualizado)',);
    expect(nomeComVersao('Unidade 3', null, desatualizado: true),
        'Unidade 3 (desatualizado)',);
    expect(nomeComVersao('Unidade 3', null), 'Unidade 3');
  });

  test('compararVersoes e celitaDesatualizado', () {
    expect(compararVersoes('1.9.0', '1.10.0'), -1);
    expect(compararVersoes('1.23.0', '1.23.0'), 0);
    expect(compararVersoes('1.24.0', '1.23.9'), 1);
    expect(compararVersoes('1.23', '1.23.0'), 0);
    expect(celitaDesatualizado('1.23.0', 'celita-0.12.0', '1.24.0'), true);
    expect(celitaDesatualizado('1.24.0', 'celita-0.12.0', '1.24.0'), false);
    expect(celitaDesatualizado(null, 'celita-0.11.0', '1.24.0'), true,
        reason: 'agente antigo não publica meta/os',);
    expect(celitaDesatualizado(null, '0.4.11', '1.24.0'), false,
        reason: 'ChromeOS não conta',);
    expect(celitaDesatualizado('1.20.0', 'celita-0.9.3', null), false,
        reason: 'sem a versão publicada, não marca',);
  });

  test('versaoMaisNovaNoIndice pega o maior celita-os-completo', () {
    const indice = '''Package: celita-os-completo
Version: 1.9.0
Architecture: amd64

Package: tema-gtk-celita
Version: 9.0.0

Package: celita-os-completo
Version: 1.23.0
Architecture: amd64

Package: celita-os-completo
Version: 1.10.0
''';
    expect(versaoMaisNovaNoIndice(indice), '1.23.0');
    expect(versaoMaisNovaNoIndice('lixo'), isNull);
  });

  test('suportaTurma: Celita >= 0.13.0, ChromeOS >= 0.7.0, nulo = antigo', () {
    expect(suportaTurma(null), isFalse);
    expect(suportaTurma(''), isFalse);
    expect(suportaTurma('   '), isFalse);
    expect(suportaTurma('celita-'), isFalse);
    expect(suportaTurma('celita-0.12.9'), isFalse);
    expect(suportaTurma('celita-0.13.0'), isTrue);
    expect(suportaTurma('celita-0.14.2'), isTrue);
    expect(suportaTurma('celita-1.0.0'), isTrue);
    expect(suportaTurma('0.6.0'), isFalse);
    expect(suportaTurma('0.6.9'), isFalse);
    expect(suportaTurma('0.7.0'), isTrue);
    expect(suportaTurma('0.10.0'), isTrue, reason: 'comparação numérica');
    // Celita 0.7.x NÃO é ChromeOS 0.7: o prefixo decide a régua.
    expect(suportaTurma('celita-0.7.0'), isFalse);
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
