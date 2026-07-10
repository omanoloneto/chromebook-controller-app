// Backup na nuvem para troca de celular (/backup/{uid}, rules owner-only):
// - keypair: teacher_key.txt cifrado pelo PIN do professor (pin_crypto) —
//   nem o banco abre; PIN errado/esquecido = backup inútil.
// - stores: os JSONs locais (turmas, nomes, regras, favoritos, prefs, aula)
//   cifrados com a chave do histórico (derivada da keypair) — disponível
//   sempre, permite sync automático sem guardar o PIN.
// Restaurar exige reiniciar o app (keypair/uid trocam por baixo de tudo).

import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../secure/crypto.dart';
import '../secure/history_crypto.dart';
import '../secure/keypair.dart';
import '../secure/pin_crypto.dart';

/// Arquivos locais que entram no backup de stores (conteúdo bruto — restaurar
/// não precisa entender o formato de cada um).
const List<String> kArquivosDeBackup = [
  'device_names.json',
  'domain_rules.json',
  'favorites.json',
  'turmas.json',
  'aula.json',
  'app_prefs.json',
];

const String _kArquivoKeypair = 'teacher_key.txt';

class BackupStore {
  BackupStore({
    required this.uid,
    required this.historyCrypto,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final String uid;

  /// Mesmo cifrador do histórico (derivado da keypair do professor).
  final SessionCrypto historyCrypto;

  final FirebaseDatabase _db;

  DatabaseReference get _raiz => _db.ref('backup/$uid');

  /// Existe backup de keypair nesta conta?
  Future<bool> existeNaNuvem() async {
    try {
      return (await _raiz.child('keypair').get()).value is String;
    } catch (_) {
      return false;
    }
  }

  /// Sobe a keypair local cifrada pelo PIN (1x ao ativar; PIN não é guardado).
  Future<void> subirKeypair(String pin) async {
    final dir = await getApplicationSupportDirectory();
    final conteudo = await File('${dir.path}/$_kArquivoKeypair').readAsString();
    final blob = await selarComPin(pin, {'keypair': conteudo});
    await _raiz.child('keypair').set(blob);
    await _raiz.child('ts').set(ServerValue.timestamp);
  }

  /// Sobe os stores locais cifrados com a chave do histórico.
  Future<void> subirStores() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final mapa = <String, String>{};
      for (final nome in kArquivosDeBackup) {
        final f = File('${dir.path}/$nome');
        if (await f.exists()) mapa[nome] = await f.readAsString();
      }
      await _raiz.child('stores').set(await historyCrypto.seal(mapa));
      await _raiz.child('ts').set(ServerValue.timestamp);
    } catch (e) {
      debugPrint('[CdA] backup de stores falhou: $e');
    }
  }

  /// Restaura keypair (via PIN) + stores no disco local. Lança
  /// [PinIncorretoException] se o PIN não abrir o envelope.
  /// O app PRECISA ser reiniciado depois.
  static Future<void> restaurar({
    required String uid,
    required String pin,
    FirebaseDatabase? database,
  }) async {
    final db = database ?? FirebaseDatabase.instance;
    final raiz = db.ref('backup/$uid');

    final blob = (await raiz.child('keypair').get()).value;
    if (blob is! String) {
      throw StateError('sem_backup');
    }
    Map<String, dynamic> aberto;
    try {
      aberto = await abrirComPin(pin, blob);
    } catch (_) {
      throw PinIncorretoException();
    }
    final keypair = aberto['keypair'];
    if (keypair is! String || keypair.isEmpty) {
      throw StateError('backup_invalido');
    }

    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/$_kArquivoKeypair').writeAsString(keypair);

    // Stores: cifrados com a chave do histórico — deriva da keypair restaurada.
    try {
      final env = (await raiz.child('stores').get()).value;
      if (env is String) {
        final crypto = await _historyCryptoDoArquivo(keypair);
        final mapa = await crypto.open(env);
        for (final entry in mapa.entries) {
          if (kArquivosDeBackup.contains(entry.key) && entry.value is String) {
            await File('${dir.path}/${entry.key}')
                .writeAsString(entry.value as String);
          }
        }
      }
    } catch (e) {
      debugPrint('[CdA] stores do backup não restauraram: $e');
      // keypair restaurada já é o essencial (PCs + histórico voltam).
    }
  }

  /// Reconstrói a DeviceKeyPair do formato do key_store
  /// ("privB64url:pubB64url") e deriva o cifrador do histórico.
  static Future<SessionCrypto> _historyCryptoDoArquivo(String conteudo) async {
    final partes = conteudo.trim().split(':');
    if (partes.length != 2) throw StateError('keypair_invalida');
    final kp = await DeviceKeyPair.fromBytes(
      pubFromB64url(partes[0]),
      pubFromB64url(partes[1]),
    );
    return historyCryptoFrom(kp);
  }
}

class PinIncorretoException implements Exception {}
