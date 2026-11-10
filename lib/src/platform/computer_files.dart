// No computador não há galeria nem compartilhar: o que o professor salva vai
// para uma pasta do app dentro de Downloads.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const String kComputerFolder = 'Controle de Aula';
const String kSavedOnComputerText = 'em Downloads, na pasta $kComputerFolder';

/// `base` é injetável para testes.
Future<File> saveBytesToComputer(Uint8List bytes, String name, {Directory? base}) async {
  final file = await _freeFile(name, base);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> copyToComputer(String path, {Directory? base}) async {
  final file = await _freeFile(path.split('/').last, base);
  return File(path).copy(file.path);
}

Future<File> _freeFile(String name, Directory? base) async {
  final downloads = base ?? await getDownloadsDirectory();
  if (downloads == null) {
    throw const FileSystemException('downloads directory not found');
  }
  final folder = Directory('${downloads.path}/$kComputerFolder');
  await folder.create(recursive: true);
  final safe = name.replaceAll('/', '-').trim();
  final dot = safe.lastIndexOf('.');
  final stem = dot > 0 ? safe.substring(0, dot) : safe;
  final extension = dot > 0 ? safe.substring(dot) : '';
  var file = File('${folder.path}/$safe');
  for (var n = 2; await file.exists(); n++) {
    file = File('${folder.path}/$stem ($n)$extension');
  }
  return file;
}
