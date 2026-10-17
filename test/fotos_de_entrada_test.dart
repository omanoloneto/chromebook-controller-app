// Fotos de início de sessão: a marca `l` do índice, a galeria de todos os PCs
// (mais nova primeiro, só PCs com Celita) e o toque que leva ao histórico só
// daquela entrada na conta.

import 'dart:convert';

import 'package:controle_de_aula/src/cloud/archive_store.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/ui/fotos_de_entrada_page.dart';
import 'package:controle_de_aula/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_pairing.dart';

// PNG de 1×1: a tela só precisa de uma imagem que abra.
final _imagem = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
const _r = 'AbCdEfGhIjKlMnOpQrStUv';
const _hora = 60 * 60 * 1000;

class _Arquivo extends ArchiveStore {
  _Arquivo(String id) : super(deviceId: id, crypto: SessionCrypto(List.filled(32, 0)));

  final Map<int, ArchivedPhoto> fotos = {};
  final List<ArchivedSession> sessoes = [];
  bool indiceFalha = false;
  final List<String> diasPedidos = [];

  void entrada(int ts, String user) => fotos[ts] = ArchivedPhoto(
        header: {'v': 1, 'type': 'archived_photo', 'ts': ts, 'motivo': 'login', 'user': user, 'login': ts - 10000},
        jpeg: _imagem,
      );

  @override
  Future<List<PhotoRef>> loginPhotos(String day) async {
    diasPedidos.add(day);
    if (indiceFalha) throw StateError('sem rede');
    return fotosDeEntrada(day, {
      for (final ts in fotos.keys)
        if (dayOf(ts) == day) ts13(ts): {'u': 'uid-pc', 'r': _r, 'l': true},
    });
  }

  @override
  Future<ArchivedPhoto> download(PhotoRef ref) async =>
      fotos[ref.ts] ?? (throw const PhotoException(PhotoFailure.deleted));

  @override
  Future<ArchivedDay> readDay(String day) async => ArchivedDay(sessions: sessoes, unreadable: 0);
}

String _hm(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<FakePairing> _abrir(WidgetTester tester, void Function(FakePairing p) preparar, {String? deviceId}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = FakePairing()..schoolUid = 'escola';
  addTearDown(p.dispose);
  preparar(p);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: FotosDeEntradaPage(pairing: p, deviceId: deviceId),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  return p;
}

void main() {
  group('índice', () {
    test('só a foto marcada com l = true é de entrada', () {
      PhotoRef? ref(Object? valor) => PhotoRef.parse('2026-10-02', '1790000000000', valor);
      expect(ref({'u': 'u', 'r': _r, 'l': true})!.entrada, isTrue);
      expect(ref({'u': 'u', 'r': _r, 'l': 'sim'})!.entrada, isFalse);
      expect(ref({'u': 'u', 'r': _r})!.entrada, isFalse, reason: 'índice dos PCs antes do Celita 1.30');
    });

    test('fotos de entrada do dia: mais nova primeiro, sem as inválidas', () {
      final fotos = fotosDeEntrada('2026-10-02', {
        '1790000000000': {'u': 'u', 'r': _r, 'l': true},
        '1790000900000': {'u': 'u', 'r': _r},
        '1790001800000': {'u': 'u', 'r': _r, 'l': true},
        'lixo': {'u': 'u', 'r': _r, 'l': true},
        '1790002700000': {'u': '../x', 'r': _r, 'l': true},
      });
      expect([for (final f in fotos) f.ts], [1790001800000, 1790000000000]);
    });
  });

  testWidgets('todos os PCs com Celita: mais nova primeiro, com o PC e a conta', (tester) async {
    final a = _Arquivo('a')..entrada(kAgoraTeste - 3 * _hora, 'aluno1');
    final b = _Arquivo('b')..entrada(kAgoraTeste - 1 * _hora, 'aluno2');
    await _abrir(tester, (p) {
      p.pc('a', nome: 'Unidade 1', ext: 'celita-1.30.0');
      p.pc('b', nome: 'Unidade 2', ext: 'celita-1.30.0');
      p.pc('c', nome: 'Chromebook', ext: '0.7.0');
      p.arquivos.addAll({'a': a, 'b': b, 'c': _Arquivo('c')..entrada(kAgoraTeste, 'x')});
    });
    final nova = find.text('${_hm(kAgoraTeste - _hora)} · Unidade 2 · aluno2');
    final velha = find.text('${_hm(kAgoraTeste - 3 * _hora)} · Unidade 1 · aluno1');
    expect(nova, findsOneWidget);
    expect(velha, findsOneWidget);
    expect(tester.getTopLeft(nova).dx, lessThan(tester.getTopLeft(velha).dx));
    expect(find.textContaining('Chromebook'), findsNothing, reason: 'PC sem Celita não tem arquivo');
  });

  testWidgets('tocar abre a foto, e Ver histórico mostra só aquela entrada', (tester) async {
    final entrou = kAgoraTeste - 2 * _hora;
    final arquivo = _Arquivo('a')..entrada(entrou + 10000, 'aluno2');
    arquivo.sessoes.addAll([
      ArchivedSession(user: 'aluno2', login: entrou)
        ..events.add(ArchivedNavEvent(ts: entrou + 60000, url: 'https://wikipedia.org/', title: 'Wikipédia')),
      ArchivedSession(user: 'aluno3', login: entrou + _hora)
        ..events.add(ArchivedNavEvent(ts: entrou + _hora + 60000, url: 'https://escola.com/', title: 'Escola')),
    ]);
    await _abrir(tester, (p) {
      p.pc('a', nome: 'Unidade 7', ext: 'celita-1.30.0');
      p.arquivos['a'] = arquivo;
    });
    await tester.tap(find.textContaining('Unidade 7'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Salvar no celular'), findsOneWidget);
    expect(find.textContaining('Entrou às ${_hm(entrou)}'), findsOneWidget);
    expect(find.textContaining('conta aluno2'), findsOneWidget);

    await tester.tap(find.text('Ver histórico'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Só a entrada da conta aluno2 às ${_hm(entrou)}'), findsOneWidget);
    expect(find.text('Wikipédia'), findsOneWidget);
    expect(find.text('Escola'), findsNothing);

    await tester.tap(find.text('Ver o dia todo'));
    await tester.pump();
    expect(find.text('Escola'), findsOneWidget);
    expect(find.text('Wikipédia'), findsOneWidget);
  });

  testWidgets('dia sem foto explica de que versão elas vêm', (tester) async {
    await _abrir(tester, (p) {
      p.pc('a', nome: 'Unidade 1', ext: 'celita-1.29.0');
      p.arquivos['a'] = _Arquivo('a');
    });
    expect(find.textContaining('Celita OS 1.30 ou mais novo'), findsOneWidget);
  });

  testWidgets('PC que não carregou avisa e os outros aparecem', (tester) async {
    await _abrir(tester, (p) {
      p.pc('a', nome: 'Unidade 1', ext: 'celita-1.30.0');
      p.pc('b', nome: 'Unidade 2', ext: 'celita-1.30.0');
      p.arquivos['a'] = _Arquivo('a')..indiceFalha = true;
      p.arquivos['b'] = _Arquivo('b')..entrada(kAgoraTeste - _hora, 'aluno2');
    });
    expect(find.text('As fotos de 1 PC não carregaram. Confira a internet do celular.'), findsOneWidget);
    expect(find.textContaining('Unidade 2'), findsOneWidget);
  });

  testWidgets('um PC só: título com o nome e só o índice dele', (tester) async {
    final a = _Arquivo('a')..entrada(kAgoraTeste - _hora, 'aluno1');
    final b = _Arquivo('b')..entrada(kAgoraTeste - _hora, 'aluno2');
    await _abrir(
      tester,
      (p) {
        p.pc('a', nome: 'Unidade 1', ext: 'celita-1.30.0');
        p.pc('b', nome: 'Unidade 2', ext: 'celita-1.30.0');
        p.arquivos.addAll({'a': a, 'b': b});
      },
      deviceId: 'a',
    );
    expect(find.text('Início de sessão — Unidade 1'), findsOneWidget);
    expect(find.text('${_hm(kAgoraTeste - _hora)} · aluno1'), findsOneWidget);
    expect(b.diasPedidos, isEmpty);
  });

  testWidgets('sem escola, explica', (tester) async {
    await _abrir(tester, (p) => p.schoolUid = null);
    expect(find.text('As fotos de início de sessão existem só nos PCs da escola.'), findsOneWidget);
  });
}
