// Seções da home: telão topo, minha aula (mesmo offline), colegas
// alfabético, disponíveis vs offline (colapsável), headers só com >=2 seções.

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

  test('ordem completa: telão, minha aula, colegas A-Z, disponíveis, offline', () {
    final s = secoesDaHome([
      pc('offline1', online: false),
      pc('livre1'),
      pc('telao', telao: true),
      pc('meu1', aula: minha),
      pc('let1', aula: leticia),
      pc('car1', aula: carlos),
    ]);
    expect(s.map((x) => x.titulo).toList(), [
      null, // telão
      'Minha aula — 8º B',
      'Aula de Prof. Carlos',
      'Aula de Prof. Letícia',
      'Disponíveis',
      'Offline',
    ]);
    expect(s.first.ids, ['telao']);
    expect(s.last.colapsavel, true);
  });

  test('vinculado na minha aula fica na seção mesmo offline', () {
    final s = secoesDaHome([
      pc('meuOff', online: false, aula: minha),
      pc('livre1'),
    ]);
    expect(s[0].titulo, 'Minha aula — 8º B');
    expect(s[0].ids, ['meuOff']);
    expect(s[1].titulo, 'Disponíveis');
  });

  test('uma seção só = lista flat sem headers', () {
    final s = secoesDaHome([pc('a'), pc('b')]);
    expect(s.length, 1);
    expect(s.single.titulo, null);
    expect(s.single.ids, ['a', 'b']);
  });

  test('só offline = flat, mas continua colapsável? não — flat sem header', () {
    final s = secoesDaHome([pc('a', online: false)]);
    expect(s.single.titulo, null);
  });

  test('turma vazia vira "Minha aula" seco', () {
    final s = secoesDaHome([
      pc('meu1', aula: (minha: true, professor: 'Eu', turma: '')),
      pc('livre1'),
    ]);
    expect(s[0].titulo, 'Minha aula');
  });

  test('ordenação por nome dentro da seção', () {
    final s = secoesDaHome([
      pc('zeta', aula: minha),
      pc('alfa', aula: minha),
      pc('livre'),
    ]);
    expect(s[0].ids, ['alfa', 'zeta']);
  });
}
