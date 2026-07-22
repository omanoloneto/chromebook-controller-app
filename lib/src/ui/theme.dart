// Tema do app (claro + escuro) e cores semânticas da aula.
// Toda cor da UI sai daqui — NUNCA usar Colors.* hardcoded nas telas
// (quebra no modo escuro). Exceção documentada: overlay da câmera no scan.

import 'package:flutter/material.dart';

/// Azul da marca (mesmo do ícone e das páginas da extensão).
const Color kSeed = Color(0xFF2962FF);

/// Versão exibida em Ajustes — manter em sincronia com o pubspec.yaml.
const String kVersaoApp = '0.15.0';

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

/// Cor das linhas finas (hairline) — estilo Instagram, por brightness.
Color hairline(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF262626) : const Color(0xFFDBDBDB);

ThemeData buildTheme(Brightness brightness) {
  final escuro = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  // Dark AMOLED: fundo 100% preto; realces pontuais (campos, chips) usam
  // cinzas quase-pretos — o grosso da UI é preto + hairlines.
  if (escuro) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF121212),
      surfaceContainer: const Color(0xFF161616),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF1F1F1F),
    );
  }
  final fundo = escuro ? Colors.black : Colors.white;
  final linha = hairline(brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: fundo,
    extensions: [CoresAula.from(scheme)],
    // AppBar chapada (estilo IG): sem elevação, sem tinta, título forte.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: fundo,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(thickness: 0.5, space: 0.5, color: linha),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // Barra inferior chapada, ícone-only (IG): sem pílula de indicador.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: fundo,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 60,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: fundo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: escuro ? const Color(0xFF121212) : const Color(0xFFF2F2F2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
    // Primário = botão cheio arredondado (estilo "Seguir" do IG).
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: linha),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
    ),
    // Sem cards no visual IG — se algo ainda usar Card, fica chapado.
    cardTheme: CardThemeData(
      elevation: 0,
      color: fundo,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 8),
  );
}
