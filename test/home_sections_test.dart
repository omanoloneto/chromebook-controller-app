// Seções da home: telão topo, na aula (mesmo desligado), colegas
// alfabético, disponíveis vs desligados (colapsável), títulos só com >=2 seções.

import 'package:controle_de_aula/src/ui/home_sections.dart';
import 'package:flutter_test/flutter_test.dart';

PcHome pc(
  String id, {
  bool online = true,
  bool telao = false,
  ({bool minha, String professor, String? turma})? aula,
}) =>
    (id: id, nome: id, online: online, telao: telao, aula: aula);

void main() {
  const minha = (minha: true, professor: 'Prof. Manoel', turma: '8º B');
  const leticia = (minha: false, professor: 'Prof. Letícia', turma: '5º A');
  const carlos = (minha: false, professor: 'Prof. Carlos', turma: null);

  test('ordem completa: telão, na aula, colegas A-Z, disponíveis, desligados', () {
    final s = secoesDaHome([
      pc('offline1', online: false),
      pc('livre1'),
      pc('telao', telao: true),
      pc('meu1', aula: minha),
      pc('let1', aula: leticia),
      pc('car1', aula: carlos),
    ]);
    expect(s.map((x) => x.titulo).toList(), [
      'Computador do Professor',
      'Na aula',
      'Aula de Prof. Carlos',
      'Aula de Prof. Letícia',
      'Disponíveis',
      'Desligados',
    ]);
    expect(s.first.ids, ['telao']);
    expect(s.last.colapsavel, true);
  });

  test('vinculado na minha aula fica na seção mesmo desligado', () {
    final s = secoesDaHome([
      pc('meuOff', online: false, aula: minha),
      pc('livre1'),
    ]);
    expect(s[0].titulo, 'Na aula');
    expect(s[0].ids, ['meuOff']);
    expect(s[1].titulo, 'Disponíveis');
  });

  test('uma seção só = lista flat sem headers', () {
    final s = secoesDaHome([pc('a'), pc('b')]);
    expect(s.length, 1);
    expect(s.single.titulo, null);
    expect(s.single.ids, ['a', 'b']);
  });

  test('só desligados = lista sem título', () {
    final s = secoesDaHome([pc('a', online: false)]);
    expect(s.single.titulo, null);
  });

  test('a turma não entra no título (ela está no alto da tela)', () {
    final s = secoesDaHome([
      pc('meu1', aula: (minha: true, professor: 'Eu', turma: '')),
      pc('livre1'),
    ]);
    expect(s[0].titulo, 'Na aula');
  });

  test('telão com mais uma seção ganha título', () {
    final s = secoesDaHome([pc('telao', telao: true), pc('livre1')]);
    expect(s.map((x) => x.titulo).toList(), ['Computador do Professor', 'Disponíveis']);
  });

  test('ordenação por nome dentro da seção', () {
    final s = secoesDaHome([
      pc('zeta', aula: minha),
      pc('alfa', aula: minha),
      pc('livre'),
    ]);
    expect(s[0].ids, ['alfa', 'zeta']);
  });

  test('unidades numeradas saem em ordem numérica (1, 3, 12, 22)', () {
    final s = secoesDaHome([
      pc('Unidade 1'),
      pc('Unidade 12'),
      pc('Unidade 22'),
      pc('Unidade 3'),
    ]);
    expect(s.single.ids, ['Unidade 1', 'Unidade 3', 'Unidade 12', 'Unidade 22']);
  });
}
