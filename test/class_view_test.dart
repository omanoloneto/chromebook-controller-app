// Visão da turma (set_class_view): builder puro.
// Fixture espelhada com a extensão: tests/classview.test.mjs usa a MESMA
// string JSON — mudou um lado, mude o outro.

import 'dart:convert';

import 'package:controle_de_aula/src/commands/class_view.dart';
import 'package:controle_de_aula/src/commands/command.dart';
import 'package:flutter_test/flutter_test.dart';

// Exemplo normativo do docs/protocolo.md §3 (set_class_view).
const _fixture = '''
{
  "rev": 1767369600000,
  "aula": { "ativa": true, "turma": "8º B" },
  "pcs": [ { "nome": "PC 07", "aluno": "William", "online": true,
             "aba": { "titulo": "Khan Academy", "dominio": "pt.khanacademy.org" },
             "alerta": "youtube.com" },
           { "nome": "PC 03", "online": false } ]
}
''';

void main() {
  test('builder reproduz a fixture normativa do protocolo', () {
    final cmd = buildSetClassView(
      rev: 1767369600000,
      aulaAtiva: true,
      turma: '8º B',
      pcs: const [
        ClassViewPc(nome: 'PC 03', online: false),
        ClassViewPc(
          nome: 'PC 07',
          online: true,
          aluno: 'William',
          abaTitulo: 'Khan Academy',
          abaDominio: 'pt.khanacademy.org',
          alerta: 'youtube.com',
        ),
      ],
    );
    expect(cmd['type'], MessageType.setClassView);
    expect(cmd['v'], kProtocolVersion);
    // Ordenação: online primeiro — PC 07 vem antes do PC 03 offline.
    expect(cmd['payload'], jsonDecode(_fixture));
  });

  test('fora de aula: ativa=false e sem turma nem aluno', () {
    final cmd = buildSetClassView(
      rev: 5,
      aulaAtiva: false,
      turma: 'não deveria vazar',
      pcs: const [ClassViewPc(nome: 'PC 01', online: true)],
    );
    final aula = (cmd['payload'] as Map)['aula'] as Map;
    expect(aula['ativa'], false);
    expect(aula.containsKey('turma'), false);
  });

  test('caps: 100 PCs viram 60; strings truncadas', () {
    final cmd = buildSetClassView(
      rev: 1,
      aulaAtiva: false,
      pcs: List.generate(
        100,
        (i) => ClassViewPc(
          nome: 'N' * 500,
          online: true,
          abaTitulo: 'T' * 500,
          abaDominio: 'd.com',
        ),
      ),
    );
    final pcs = (cmd['payload'] as Map)['pcs'] as List;
    expect(pcs.length, kMaxClassViewPcs);
    expect(((pcs.first as Map)['nome'] as String).length, kMaxClassViewNome);
    expect(
      (((pcs.first as Map)['aba'] as Map)['titulo'] as String).length,
      kMaxClassViewTitulo,
    );
  });

  test('ordenação determinística: online desc, nome asc (case-insensitive)', () {
    final cmd = buildSetClassView(
      rev: 1,
      aulaAtiva: false,
      pcs: const [
        ClassViewPc(nome: 'zeta', online: true),
        ClassViewPc(nome: 'Alfa', online: false),
        ClassViewPc(nome: 'beta', online: true),
      ],
    );
    final nomes =
        ((cmd['payload'] as Map)['pcs'] as List).map((p) => (p as Map)['nome']);
    expect(nomes, ['beta', 'zeta', 'Alfa']);
  });

  test('fingerprint ignora rev e id: estável entre pushes iguais', () {
    ClassViewPc pc() => const ClassViewPc(nome: 'PC 01', online: true);
    final a = buildSetClassView(rev: 1, aulaAtiva: false, pcs: [pc()]);
    final b = buildSetClassView(rev: 2, aulaAtiva: false, pcs: [pc()]);
    expect(classViewFingerprint(a), classViewFingerprint(b));
    final c = buildSetClassView(rev: 3, aulaAtiva: true, pcs: [pc()]);
    expect(classViewFingerprint(a) == classViewFingerprint(c), false);
  });

  test('dominioDaUrl: extrai host sem www; inválida vira null', () {
    expect(dominioDaUrl('https://www.youtube.com/watch?v=x'), 'youtube.com');
    expect(dominioDaUrl('https://pt.khanacademy.org/math'), 'pt.khanacademy.org');
    expect(dominioDaUrl('lixo'), null);
    expect(dominioDaUrl(null), null);
  });
}
