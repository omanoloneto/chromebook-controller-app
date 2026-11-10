// Porta do Storage: fotos e mídia cifradas.

import 'dart:typed_data';

abstract interface class BlobStorage {
  Future<Uint8List?> getData(String path, int maxSize);
  Future<void> delete(String path);
}
