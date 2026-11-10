// Onde o app está aberto: no celular do professor ou no computador da escola
// (Celita OS). A base de código é a mesma; o que só existe no celular (câmera,
// galeria, push, serviço em primeiro plano) pergunta aqui.

import 'dart:io';

import 'package:flutter/foundation.dart';

@visibleForTesting
bool? onComputerOverride;

bool get onComputer => onComputerOverride ?? Platform.isLinux;

/// Como os textos chamam o aparelho onde o app está aberto ("Confira a
/// internet do celular" / "deste computador").
String get ofThisDeviceText => onComputer ? 'deste computador' : 'do celular';
