// Portão de entrada: sem Google pede login; sem vínculo espera e confere de
// novo sozinho; liberado abre no papel certo; sem internet usa o papel guardado.

import 'dart:async';

import 'package:controle_de_aula/src/backend/backend.dart';
import 'package:controle_de_aula/src/pairing/acesso_controller.dart';
import 'package:controle_de_aula/src/ui/acesso_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _User implements AuthUser {
  _User({this.hasGoogle = true});

  @override
  String get uid => 'u1';
  @override
  String? get email => 'bia@escola.com';
  @override
  final bool hasGoogle;
  @override
  String? get googleEmail => email;
  @override
  Future<void> refreshIdToken() async {}
}

void main() {
  test('sem conta Google: pede para entrar', () async {
    final a = AcessoController(usuario: () => _User(hasGoogle: false), papelDe: (_) async => PapelNaEscola.professor);
    await a.verificar();
    expect(a.estado, EstadoDoAcesso.entrar);
    final b = AcessoController(usuario: () => null);
    await b.verificar();
    expect(b.estado, EstadoDoAcesso.entrar);
  });

  test('sem vínculo confere de novo e libera sozinho no papel certo', () async {
    PapelNaEscola? papel;
    var consultas = 0;
    final a = AcessoController(
      usuario: _User.new,
      papelDe: (_) async {
        consultas++;
        return papel;
      },
      intervalo: const Duration(milliseconds: 20),
    );
    await a.verificar();
    expect((a.estado, a.email), (EstadoDoAcesso.semVinculo, 'bia@escola.com'));
    papel = PapelNaEscola.monitora;
    final liberou = Completer<void>();
    a.addListener(() {
      if (a.estado == EstadoDoAcesso.liberado && !liberou.isCompleted) liberou.complete();
    });
    await liberou.future.timeout(const Duration(seconds: 2));
    expect(a.papel, PapelNaEscola.monitora);
    expect(consultas, greaterThanOrEqualTo(2));
    final antes = consultas;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(consultas, antes, reason: 'liberado, para de conferir');
    a.dispose();
  });

  test('sem internet: segue com o papel guardado, ou espera e tenta de novo', () async {
    final guardado = AcessoController(
      usuario: _User.new,
      papelDe: (_) async => throw Exception('offline'),
      papelGuardado: PapelNaEscola.professor,
    );
    await guardado.verificar();
    expect((guardado.estado, guardado.papel), (EstadoDoAcesso.liberado, PapelNaEscola.professor));
    final novo = AcessoController(
      usuario: _User.new,
      papelDe: (_) async => throw Exception('offline'),
      intervalo: const Duration(hours: 1),
    );
    await novo.verificar();
    expect((novo.estado, novo.semInternet), (EstadoDoAcesso.verificando, true));
    novo.dispose();
  });

  testWidgets('tela sem vínculo mostra o e-mail para informar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var saiu = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TelaSemVinculo(email: 'bia@escola.com', onOutraConta: () async => saiu = true),
      ),
    );
    expect(find.textContaining('administrador da sua escola'), findsOneWidget);
    expect(find.text('Informe este e-mail:'), findsOneWidget);
    expect(find.text('bia@escola.com'), findsOneWidget);
    await tester.tap(find.text('Usar outra conta'));
    expect(saiu, isTrue);
  });
}
