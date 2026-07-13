// Alvo dos comandos de turma: só vinculados durante aula ativa; todos fora
// de aula; PC do professor nunca entra.

import 'package:controle_de_aula/src/cloud/broadcast_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const todos = ['pc1', 'pc2', 'pc3', 'telao'];

  test('aula ativa: só os vinculados, sem o professor', () {
    final alvo = alvoDeBroadcast(
      aulaAtiva: true,
      vinculados: ['pc1', 'pc3', 'telao'], // telao vinculado por engano
      todos: todos,
      pcProfessorId: 'telao',
    );
    expect(alvo, ['pc1', 'pc3']); // telao removido mesmo estando em vinculados
  });

  test('aula ativa sem vínculos: alvo vazio', () {
    final alvo = alvoDeBroadcast(
      aulaAtiva: true,
      vinculados: const [],
      todos: todos,
      pcProfessorId: 'telao',
    );
    expect(alvo, isEmpty);
  });

  test('fora de aula: todos menos o professor', () {
    final alvo = alvoDeBroadcast(
      aulaAtiva: false,
      vinculados: const [],
      todos: todos,
      pcProfessorId: 'telao',
    );
    expect(alvo, ['pc1', 'pc2', 'pc3']);
  });

  test('sem professor marcado: todos entram (fora de aula)', () {
    final alvo = alvoDeBroadcast(
      aulaAtiva: false,
      vinculados: const [],
      todos: todos,
      pcProfessorId: null,
    );
    expect(alvo, todos);
  });
}
