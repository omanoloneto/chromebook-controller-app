// Tema do app (claro + escuro) e cores semânticas da aula.
// Toda cor da UI sai daqui — NUNCA usar Colors.* hardcoded nas telas
// (quebra no modo escuro). Exceção documentada: overlay da câmera no scan.

import 'package:flutter/material.dart';

/// Azul da marca (mesmo do ícone e das páginas da extensão).
const Color kSeed = Color(0xFF2962FF);

/// Versão exibida em Ajustes — manter em sincronia com o pubspec.yaml.
const String kVersaoApp = '0.9.0';

/// Cores semânticas que o ColorScheme não cobre. `online` é fixo por
/// brightness (o tertiary do seed azul sai lilás — verde/teal é o código
/// cultural de "conectado"); o resto deriva do scheme quando possível.
@immutable
class CoresAula extends ThemeExtension<CoresAula> {
  const CoresAula({
    required this.online,
    required this.onOnline,
    required this.offline,
    required this.alertaBg,
    required this.alertaFg,
    required this.atencao,
    required this.favorito,
  });

  final Color online; // dot/ícone de PC online, snackbar de sucesso
  final Color onOnline; // conteúdo sobre `online`
  final Color offline; // dot/ícone de PC offline
  final Color alertaBg; // fundo de card/banner em alerta
  final Color alertaFg; // ícone/texto do alerta
  final Color atencao; // regra "alertar" (distinta do "bloquear" vermelho)
  final Color favorito; // estrela de favorito

  factory CoresAula.from(ColorScheme scheme) {
    final escuro = scheme.brightness == Brightness.dark;
    return CoresAula(
      online: escuro ? const Color(0xFF4DB6AC) : const Color(0xFF00897B),
      onOnline: escuro ? const Color(0xFF00332E) : Colors.white,
      offline: scheme.outline,
      alertaBg: scheme.errorContainer,
      alertaFg: scheme.onErrorContainer,
      atencao: escuro ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00),
      favorito: escuro ? const Color(0xFFFFD54F) : const Color(0xFFF9A825),
    );
  }

  @override
  CoresAula copyWith({
    Color? online,
    Color? onOnline,
    Color? offline,
    Color? alertaBg,
    Color? alertaFg,
    Color? atencao,
    Color? favorito,
  }) {
    return CoresAula(
      online: online ?? this.online,
      onOnline: onOnline ?? this.onOnline,
      offline: offline ?? this.offline,
      alertaBg: alertaBg ?? this.alertaBg,
      alertaFg: alertaFg ?? this.alertaFg,
      atencao: atencao ?? this.atencao,
      favorito: favorito ?? this.favorito,
    );
  }

  @override
  CoresAula lerp(ThemeExtension<CoresAula>? other, double t) {
    if (other is! CoresAula) return this;
    return CoresAula(
      online: Color.lerp(online, other.online, t)!,
      onOnline: Color.lerp(onOnline, other.onOnline, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      alertaBg: Color.lerp(alertaBg, other.alertaBg, t)!,
      alertaFg: Color.lerp(alertaFg, other.alertaFg, t)!,
      atencao: Color.lerp(atencao, other.atencao, t)!,
      favorito: Color.lerp(favorito, other.favorito, t)!,
    );
  }
}

/// Atalho: `cores(context).online`.
CoresAula cores(BuildContext context) =>
    Theme.of(context).extension<CoresAula>()!;

ThemeData buildTheme(Brightness brightness) {
  var scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  // Dark AMOLED: fundo 100% preto; cards/navbar ficam nos surfaceContainer*
  // (cinza escuro), destacando sobre o preto puro.
  if (brightness == Brightness.dark) {
    scheme = scheme.copyWith(surface: Colors.black);
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        brightness == Brightness.dark ? Colors.black : null,
    extensions: [CoresAula.from(scheme)],
    appBarTheme: const AppBarTheme(centerTitle: false),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // Alvos de toque generosos: professor em pé, uma mão.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
  );
}
