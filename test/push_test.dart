// Push dos recados com o app fechado: envelopes do up/ selados pelo agente do
// Celita (vetor push-v1, gerado com controle_de_aula.crypto) no formato que a
// Cloud Function avisarRecado manda, decifrados com a chave do professor.

import 'dart:convert';
import 'dart:io';

import 'package:controle_de_aula/src/cloud/up_router.dart';
import 'package:controle_de_aula/src/secure/crypto.dart';
import 'package:controle_de_aula/src/secure/keypair.dart';
import 'package:controle_de_aula/src/service/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vetor = jsonDecode(File('test/fixtures/push-v1.json').readAsStringSync()) as Map<String, dynamic>;
  final agoraMs = vetor['agoraMs'] as int;
  final recados = (vetor['recados'] as List).cast<Map<String, dynamic>>();

  Future<DeviceKeyPair> professor() {
    final partes = (vetor['professor'] as String).split(':');
    return DeviceKeyPair.fromBytes(pubFromB64url(partes[0]), pubFromB64url(partes[1]));
  }

  Future<RecadoDoPush?> abrir(Map<String, dynamic> dados, {String Function(String, String)? nome}) async =>
      abrirRecado(dados, professor: await professor(), nome: nome ?? (_, label) => label, agoraMs: agoraMs);

  test('chat, pedido e mão viram a mesma notificação do caminho ao vivo', () async {
    for (final r in recados) {
      final dados = Map<String, dynamic>.from(r['dados'] as Map);
      final recado = await abrir(dados);
      final esperado = r['esperado'] as Map<String, dynamic>?;
      if (esperado == null) {
        expect(recado, isNull, reason: 'velho ou de outra chave: ${dados['k']}');
        continue;
      }
      expect(recado, isNotNull);
      expect((recado!.k, recado.titulo, recado.corpo), (esperado['k'], esperado['titulo'], esperado['corpo']));
      expect(recado.deviceId, 'pc-unidade-12');
      expect(recado.ts, pushIdMs(dados['k'] as String), reason: 'a hora é a do servidor, como ao vivo');
    }
  });

  test('o nome do PC vem dos arquivos do app quando há', () async {
    final dados = Map<String, dynamic>.from(recados.first['dados'] as Map);
    final recado = await abrir(dados, nome: (deviceId, _) => deviceId == 'pc-unidade-12' ? 'Ana Souza' : '?');
    expect(recado!.titulo, 'Ana Souza');
    final pedido = await abrir(
      Map<String, dynamic>.from(recados[1]['dados'] as Map),
      nome: (_, __) => 'Ana Souza',
    );
    expect(pedido!.corpo, 'Ana Souza: wikipedia.org');
  });

  test('chat para outra pessoa da equipe não toca; para mim ou sem destino, toca', () async {
    final modelo = recados.firstWhere((r) => (r['esperado'] as Map?)?['k'] == 'chat');
    final pc = await DeviceKeyPair.generate();
    final cripto = SessionCrypto(await pc.deriveSessionKey((await professor()).publicBytes));
    Future<RecadoDoPush?> com(String? para, {String? meuUid}) async {
      final env = await cripto.seal({
        'sid': 1,
        'seq': 1,
        'ts': agoraMs,
        'v': 1,
        'type': 'chat',
        'mid': 'a' * 16,
        'payload': {'texto': 'Socorro', if (para != null) 'para': para, 'nome': 'Ana', 'ano': 5},
      });
      final dados = {...Map<String, dynamic>.from(modelo['dados'] as Map), 'e': env, 'p': pubToB64url(pc.publicBytes)};
      return abrirRecado(dados, professor: await professor(), nome: (_, l) => l, agoraMs: agoraMs, meuUid: meuUid);
    }

    expect(await com('uid-bia', meuUid: 'uid-eu'), isNull);
    expect((await com('uid-eu', meuUid: 'uid-eu'))?.corpo, 'Socorro');
    expect((await com(null, meuUid: 'uid-eu'))?.corpo, 'Socorro');
    expect((await com('uid-bia'))?.corpo, 'Socorro', reason: 'sem uid guardado: toca como antes');
  });

  test('fora do formato não toca', () async {
    final base = Map<String, dynamic>.from(recados.first['dados'] as Map);
    for (final dados in <Map<String, dynamic>>[
      {},
      {...base, 't': 'outro'},
      {...base}..remove('e'),
      {...base}..remove('p'),
      {...base, 'e': 'não é base64'},
      {...base, 'k': 'curto'},
      {...base, 'd': ''},
    ]) {
      expect(await abrir(dados), isNull, reason: '$dados');
    }
  });

  test('a chave do token cabe no RTDB e não muda', () {
    const token = 'dQw4w9WgXcQ:APA91bH-abc_def/ghi.jkl';
    final chave = chaveDoToken(token);
    expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(chave), isTrue);
    expect(chaveDoToken(token), chave);
    expect(chaveDoToken('$token!'), isNot(chave));
  });
}
