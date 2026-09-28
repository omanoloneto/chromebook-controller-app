// Criptografia ponta-a-ponta dos comandos — ver docs/protocolo.md.
// Precisa casar EXATAMENTE com a extensão (src/lib/crypto.js).
//
// Formato no fio (base64 padrão): nonce(12) || ciphertext || tag(16)
// Cifra: AES-256-GCM. Texto em claro: JSON UTF-8.
// SEM AAD — seq/ts viajam dentro do JSON (já autenticado pelo GCM).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Foto arquivada já aberta ("foto-v1", docs/protocolo.md).
class ArchivedPhoto {
  const ArchivedPhoto({required this.header, required this.jpeg});

  final Map<String, dynamic> header;
  final Uint8List jpeg;

  int get ts => (header['ts'] as num).toInt();
  String? get motivo => header['motivo'] as String?;
  String? get user => header['user'] as String?;
  int? get login => (header['login'] as num?)?.toInt();
}

class SessionCrypto {
  SessionCrypto(this.key);

  /// Chave de 32 bytes (256 bits).
  final List<int> key;

  final AesGcm _algo = AesGcm.with256bits();
  SecretKey? _sk;

  Future<SecretKey> _secretKey() async =>
      _sk ??= await _algo.newSecretKeyFromBytes(key);

  /// Gera uma chave aleatória de 32 bytes.
  static List<int> generateKey() {
    final r = Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256));
  }

  static String keyToBase64url(List<int> key) =>
      base64Url.encode(key).replaceAll('=', '');

  static List<int> keyFromBase64url(String s) {
    final clean = s.trim();
    final pad = (4 - clean.length % 4) % 4;
    return base64Url.decode(clean + ('=' * pad));
  }

  /// Cifra um objeto. `nonce` opcional só para testes determinísticos.
  Future<String> seal(Map<String, dynamic> obj, {List<int>? nonce}) async {
    final n = nonce ?? _algo.newNonce();
    final plaintext = utf8.encode(jsonEncode(obj));
    final box = await _algo.encrypt(
      plaintext,
      secretKey: await _secretKey(),
      nonce: n,
    );
    final out = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return base64.encode(out);
  }

  /// Decifra um envelope (base64). Lança em caso de falha de autenticação.
  Future<Map<String, dynamic>> open(String envelopeB64) async {
    final bytes = base64.decode(envelopeB64.trim());
    if (bytes.length < 12 + 16) {
      throw const FormatException('envelope_curto');
    }
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(12, bytes.length - 16);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final plaintext = await _algo.decrypt(box, secretKey: await _secretKey());
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  /// Objeto foto-v1 (binário): nonce(12) || AES-GCM(utf8(header) || 0x0A || jpeg).
  /// Só o agente do Celita gera fotos; aqui serve para teste.
  Future<Uint8List> sealPhoto(
    Map<String, dynamic> header,
    List<int> jpeg, {
    List<int>? nonce,
  }) async {
    final n = nonce ?? _algo.newNonce();
    final plaintext = <int>[...utf8.encode(jsonEncode(header)), 0x0A, ...jpeg];
    final box = await _algo.encrypt(
      plaintext,
      secretKey: await _secretKey(),
      nonce: n,
    );
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Abre um objeto foto-v1. [ts] = ts13 do nome do arquivo: um cabeçalho
  /// com outro ts é recusado (objeto trocado de lugar no bucket).
  Future<ArchivedPhoto> openPhoto(List<int> data, {required int ts}) async {
    if (data.length < 12 + 16 + 1) {
      throw const FormatException('foto_curta');
    }
    final box = SecretBox(
      data.sublist(12, data.length - 16),
      nonce: data.sublist(0, 12),
      mac: Mac(data.sublist(data.length - 16)),
    );
    final plaintext = await _algo.decrypt(box, secretKey: await _secretKey());
    final sep = plaintext.indexOf(0x0A);
    if (sep < 0) throw const FormatException('foto_sem_separador');
    final header = jsonDecode(utf8.decode(plaintext.sublist(0, sep)));
    if (header is! Map<String, dynamic> ||
        header['v'] != 1 ||
        header['type'] != 'archived_photo' ||
        header['ts'] is! num ||
        (header['ts'] as num).toInt() != ts) {
      throw const FormatException('foto_cabecalho_invalido');
    }
    return ArchivedPhoto(
      header: header,
      jpeg: Uint8List.fromList(plaintext.sublist(sep + 1)),
    );
  }
}
