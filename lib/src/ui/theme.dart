// Tema do app (claro + escuro) e cores semânticas da aula.
// Toda cor da UI sai daqui — NUNCA usar Colors.* hardcoded nas telas
// (quebra no modo escuro). Exceção documentada: overlay da câmera no scan.
//
// Linguagem visual: fundo neutro, conteúdo em cartões brancos com borda fina,
// texto em Inter (a mesma fonte do Celita OS) e o azul da marca só para o que
// é ação ou seleção.

import 'package:flutter/material.dart';

/// Azul da marca (mesmo do ícone e das páginas da extensão).
const Color kSeed = Color(0xFF2962FF);

/// Versão exibida em Ajustes. Um teste confere com o pubspec.yaml.
const String kVersaoApp = '0.29.0';

/// Fonte do app, embutida em assets/fonts.
const String kFonte = 'Inter';

/// Cantos: cartões e diálogos (16), botões e campos (12), selos (8).
const double kRaioCartao = 16;
const double kRaioBotao = 12;
const double kRaioSelo = 8;

class _Paleta {
  const _Paleta({
    required this.fundo,
    required this.superficie,
    required this.superficieAlta,
    required this.borda,
    required this.texto,
    required this.textoSecundario,
    required this.primaria,
    required this.noPrimaria,
    required this.primariaSuave,
    required this.noPrimariaSuave,
    required this.erro,
    required this.erroSuave,
    required this.noErroSuave,
  });

  final Color fundo;
  final Color superficie;
  final Color superficieAlta;
  final Color borda;
  final Color texto;
  final Color textoSecundario;
  final Color primaria;
  final Color noPrimaria;
  final Color primariaSuave;
  final Color noPrimariaSuave;
  final Color erro;
  final Color erroSuave;
  final Color noErroSuave;

  static const claro = _Paleta(
    fundo: Color(0xFFF4F5F7),
    superficie: Color(0xFFFFFFFF),
    superficieAlta: Color(0xFFEEF0F3),
    borda: Color(0xFFE2E5EA),
    texto: Color(0xFF14171C),
    textoSecundario: Color(0xFF5E6672),
    primaria: kSeed,
    noPrimaria: Color(0xFFFFFFFF),
    primariaSuave: Color(0xFFE8EEFF),
    noPrimariaSuave: Color(0xFF1B3FB5),
    erro: Color(0xFFD92D20),
    erroSuave: Color(0xFFFDECEA),
    noErroSuave: Color(0xFF8A1C12),
  );

  static const escuro = _Paleta(
    fundo: Color(0xFF0B0C0E),
    superficie: Color(0xFF16181C),
    superficieAlta: Color(0xFF1F2227),
    borda: Color(0xFF2B2F36),
    texto: Color(0xFFECEEF2),
    textoSecundario: Color(0xFFA0A7B2),
    primaria: Color(0xFF7D9BFF),
    noPrimaria: Color(0xFF0A1A4D),
    primariaSuave: Color(0xFF1C2848),
    noPrimariaSuave: Color(0xFFC9D6FF),
    erro: Color(0xFFFF6B5E),
    erroSuave: Color(0xFF3A1714),
    noErroSuave: Color(0xFFFFC9C3),
  );
}

/// Cores semânticas que o ColorScheme não cobre. `online` é verde por
/// brightness (o tertiary do seed azul sai lilás — verde é o código cultural
/// de "conectado"); o resto deriva do scheme quando possível.
@immutable
class CoresAula extends ThemeExtension<CoresAula> {
  const CoresAula({
    required this.online,
    required this.onOnline,
    required this.offline,
    required this.alertaBg,
    required this.alertaFg,
    required this.atencao,
    required this.atencaoBg,
    required this.sucessoBg,
    required this.favorito,
  });

  final Color online; // dot/ícone de PC online, snackbar de sucesso
  final Color onOnline; // conteúdo sobre `online`
  final Color offline; // dot/ícone de PC offline
  final Color alertaBg; // fundo de card/selo em alerta
  final Color alertaFg; // ícone/texto do alerta
  final Color atencao; // regra "alertar", mão levantada, trava
  final Color atencaoBg; // fundo dos selos de atenção
  final Color sucessoBg; // fundo dos selos de sucesso
  final Color favorito; // estrela de favorito

  factory CoresAula.from(ColorScheme scheme) {
    final escuro = scheme.brightness == Brightness.dark;
    return CoresAula(
      online: escuro ? const Color(0xFF4ADE80) : const Color(0xFF12924F),
      onOnline: escuro ? const Color(0xFF052E16) : Colors.white,
      offline: scheme.outline,
      alertaBg: scheme.errorContainer,
      alertaFg: scheme.onErrorContainer,
      atencao: escuro ? const Color(0xFFFBBF4D) : const Color(0xFFB54708),
      atencaoBg: escuro ? const Color(0xFF3A2A0E) : const Color(0xFFFEF0C7),
      sucessoBg: escuro ? const Color(0xFF0E2E1C) : const Color(0xFFDCFCE7),
      favorito: escuro ? const Color(0xFFFFD54F) : const Color(0xFFF59E0B),
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
    Color? atencaoBg,
    Color? sucessoBg,
    Color? favorito,
  }) {
    return CoresAula(
      online: online ?? this.online,
      onOnline: onOnline ?? this.onOnline,
      offline: offline ?? this.offline,
      alertaBg: alertaBg ?? this.alertaBg,
      alertaFg: alertaFg ?? this.alertaFg,
      atencao: atencao ?? this.atencao,
      atencaoBg: atencaoBg ?? this.atencaoBg,
      sucessoBg: sucessoBg ?? this.sucessoBg,
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
      atencaoBg: Color.lerp(atencaoBg, other.atencaoBg, t)!,
      sucessoBg: Color.lerp(sucessoBg, other.sucessoBg, t)!,
      favorito: Color.lerp(favorito, other.favorito, t)!,
    );
  }
}

/// Atalho: `cores(context).online`.
CoresAula cores(BuildContext context) =>
    Theme.of(context).extension<CoresAula>()!;

/// Cor das linhas finas (bordas de cartão, divisores), por brightness.
Color hairline(Brightness b) => b == Brightness.dark
    ? _Paleta.escuro.borda
    : _Paleta.claro.borda;

TextTheme _textos(Color texto, Color secundario) {
  TextStyle s(double tamanho, double altura, FontWeight peso, {Color? cor, double espaco = 0}) =>
      TextStyle(
        fontFamily: kFonte,
        fontSize: tamanho,
        height: altura / tamanho,
        fontWeight: peso,
        letterSpacing: espaco,
        color: cor ?? texto,
      );
  return TextTheme(
    displaySmall: s(32, 40, FontWeight.w700, espaco: -0.5),
    headlineMedium: s(26, 32, FontWeight.w700, espaco: -0.4),
    headlineSmall: s(22, 28, FontWeight.w700, espaco: -0.3),
    titleLarge: s(20, 26, FontWeight.w600, espaco: -0.2),
    titleMedium: s(16, 22, FontWeight.w600, espaco: -0.1),
    titleSmall: s(14, 20, FontWeight.w600),
    bodyLarge: s(16, 24, FontWeight.w400),
    bodyMedium: s(15, 21, FontWeight.w400),
    bodySmall: s(13, 18, FontWeight.w400, cor: secundario),
    labelLarge: s(15, 20, FontWeight.w600),
    labelMedium: s(13, 18, FontWeight.w500),
    labelSmall: s(12, 16, FontWeight.w500, espaco: 0.1),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final escuro = brightness == Brightness.dark;
  final p = escuro ? _Paleta.escuro : _Paleta.claro;
  final scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness).copyWith(
    primary: p.primaria,
    onPrimary: p.noPrimaria,
    primaryContainer: p.primariaSuave,
    onPrimaryContainer: p.noPrimariaSuave,
    secondaryContainer: p.primariaSuave,
    onSecondaryContainer: p.noPrimariaSuave,
    surface: p.superficie,
    onSurface: p.texto,
    onSurfaceVariant: p.textoSecundario,
    surfaceContainerLowest: p.superficie,
    surfaceContainerLow: p.superficie,
    surfaceContainer: p.superficieAlta,
    surfaceContainerHigh: p.superficieAlta,
    surfaceContainerHighest: p.superficieAlta,
    outline: escuro ? const Color(0xFF6B7280) : const Color(0xFF9AA1AC),
    outlineVariant: p.borda,
    error: p.erro,
    errorContainer: p.erroSuave,
    onErrorContainer: p.noErroSuave,
    surfaceTint: Colors.transparent,
  );
  final textos = _textos(p.texto, p.textoSecundario);
  final borda = BorderSide(color: p.borda);
  RoundedRectangleBorder cantos(double raio, {BorderSide lado = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(raio), side: lado);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kFonte,
    textTheme: textos,
    scaffoldBackgroundColor: p.fundo,
    canvasColor: p.fundo,
    extensions: [CoresAula.from(scheme)],
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: p.fundo,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.texto,
      titleSpacing: 20,
      titleTextStyle: textos.headlineSmall,
      iconTheme: IconThemeData(color: p.texto, size: 24),
      actionsIconTheme: IconThemeData(color: p.texto, size: 24),
    ),
    dividerTheme: DividerThemeData(thickness: 1, space: 1, color: p.borda),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.superficie,
      surfaceTintColor: Colors.transparent,
      shape: cantos(kRaioCartao, lado: borda),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 10,
      horizontalTitleGap: 14,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: p.textoSecundario,
      titleTextStyle: textos.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: textos.bodySmall,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.superficie,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primariaSuave,
      indicatorShape: cantos(kRaioBotao),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.noPrimariaSuave : p.textoSecundario,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => textos.labelSmall?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.texto : p.textoSecundario,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.primaria,
      unselectedLabelColor: p.textoSecundario,
      labelStyle: textos.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textos.labelMedium,
      indicatorColor: p.primaria,
      dividerColor: p.borda,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: p.superficie,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.borda,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.superficie,
      surfaceTintColor: Colors.transparent,
      shape: cantos(20),
      titleTextStyle: textos.titleLarge,
      contentTextStyle: textos.bodyMedium?.copyWith(color: p.textoSecundario),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: cantos(kRaioBotao, lado: borda),
      textStyle: textos.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: escuro ? const Color(0xFF2A2E35) : const Color(0xFF1C2027),
      contentTextStyle: textos.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: escuro ? p.primaria : const Color(0xFF9DB6FF),
      shape: cantos(kRaioBotao),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.superficieAlta,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRaioBotao),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRaioBotao),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRaioBotao),
        borderSide: BorderSide(color: p.primaria, width: 1.5),
      ),
      hintStyle: textos.bodyMedium?.copyWith(color: p.textoSecundario),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: textos.labelLarge,
        shape: cantos(kRaioBotao),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        foregroundColor: p.texto,
        textStyle: textos.labelLarge,
        side: borda,
        shape: cantos(kRaioBotao),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        textStyle: textos.labelLarge,
        shape: cantos(kRaioBotao),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primaria,
      foregroundColor: p.noPrimaria,
      elevation: 2,
      highlightElevation: 3,
      extendedTextStyle: textos.labelLarge,
      shape: cantos(kRaioCartao),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.superficieAlta,
      selectedColor: p.primariaSuave,
      side: BorderSide.none,
      labelStyle: textos.labelMedium,
      shape: cantos(kRaioSelo),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: p.primariaSuave,
        selectedForegroundColor: p.noPrimariaSuave,
        side: borda,
        textStyle: textos.labelMedium,
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: p.erro,
      textStyle: textos.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primaria,
      linearTrackColor: p.superficieAlta,
    ),
  );
}
