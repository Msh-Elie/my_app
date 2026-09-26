import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// =========================================================================
/// Système de design SwitchMoney
/// =========================================================================
/// Un seul endroit définit les couleurs, les rayons, les ombres et la
/// typographie de l'application. Les écrans ne codent plus de couleur en dur :
/// ils lisent des *jetons sémantiques* (`context.colors.surface`,
/// `context.colors.textMuted`, …) qui ont une valeur en clair et une en
/// sombre. C'est ce qui permet au thème de basculer d'un bloc, et c'est aussi
/// ce qui rend l'ensemble cohérent d'un écran à l'autre.
///
/// Repères de lisibilité (WCAG AA) :
/// - l'orange de marque #FE6F0B est trop clair pour du texte sur fond blanc
///   (~2.9:1) : sur fond clair on utilise [AppColors.brandText] (#B45309),
///   l'orange vif restant réservé aux aplats et aux accents graphiques ;
/// - sur un bouton orange plein, le libellé est encre foncée (~7:1) et non
///   blanc (~2.6:1).
/// =========================================================================

/// Orange de marque, identique dans les deux thèmes.
const Color kBrand = Color(0xFFFE6F0B);

/// Échelle d'espacement (multiples de 4).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Échelle de rayons.
abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Jetons de couleur sémantiques, déclinés en clair et en sombre.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Fond de page.
  final Color canvas;

  /// Surface des cartes posées sur [canvas].
  final Color surface;

  /// Surface secondaire : champs de saisie, puces, lignes de détail.
  final Color surfaceMuted;

  /// Surface d'un élément survolé / sélectionné.
  final Color surfaceHover;

  /// Trait de séparation discret.
  final Color border;

  /// Trait de séparation appuyé (contour de carte importante).
  final Color borderStrong;

  /// Texte principal.
  final Color textPrimary;

  /// Texte secondaire (sous-titres, libellés).
  final Color textSecondary;

  /// Texte tertiaire (indications, méta-données).
  final Color textMuted;

  /// Orange de marque en aplat.
  final Color brand;

  /// Orange lisible en **texte** sur le fond du thème courant.
  final Color brandText;

  /// Voile orange très léger (fonds de puces, encarts d'information).
  final Color brandSurface;

  /// Contour orange discret.
  final Color brandBorder;

  /// Encre posée sur un aplat orange.
  final Color onBrand;

  final Color success;
  final Color successSurface;
  final Color warning;
  final Color warningSurface;
  final Color danger;
  final Color dangerSurface;

  /// Ombre portée des cartes.
  final List<BoxShadow> cardShadow;

  /// Ombre portée des éléments en relief (bouton principal, feuille modale).
  final List<BoxShadow> raisedShadow;

  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brand,
    required this.brandText,
    required this.brandSurface,
    required this.brandBorder,
    required this.onBrand,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.danger,
    required this.dangerSurface,
    required this.cardShadow,
    required this.raisedShadow,
  });

  static const AppColors light = AppColors(
    canvas: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F2F5),
    surfaceHover: Color(0xFFE9ECF1),
    border: Color(0xFFE4E7EC),
    borderStrong: Color(0xFFD0D5DD),
    textPrimary: Color(0xFF101828),
    textSecondary: Color(0xFF515C6B),
    textMuted: Color(0xFF8A93A1),
    brand: kBrand,
    brandText: Color(0xFFB45309),
    brandSurface: Color(0xFFFFF3E8),
    brandBorder: Color(0xFFFFD5B0),
    onBrand: Color(0xFF1B1200),
    success: Color(0xFF067647),
    successSurface: Color(0xFFE7F6EF),
    warning: Color(0xFF9A6300),
    warningSurface: Color(0xFFFDF3E2),
    danger: Color(0xFFB42318),
    dangerSurface: Color(0xFFFDECEA),
    cardShadow: [
      BoxShadow(
        color: Color(0x0D101828),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x1A101828),
        blurRadius: 28,
        offset: Offset(0, 10),
      ),
    ],
  );

  static const AppColors dark = AppColors(
    canvas: Color(0xFF0B0D11),
    surface: Color(0xFF15181E),
    surfaceMuted: Color(0xFF1C2027),
    surfaceHover: Color(0xFF232833),
    border: Color(0xFF262B34),
    borderStrong: Color(0xFF353C48),
    textPrimary: Color(0xFFF3F5F7),
    textSecondary: Color(0xFFA6AEBB),
    textMuted: Color(0xFF6F7886),
    brand: kBrand,
    brandText: Color(0xFFFF9048),
    brandSurface: Color(0x1FFE6F0B),
    brandBorder: Color(0x3DFE6F0B),
    onBrand: Color(0xFF1B1200),
    success: Color(0xFF3DD68C),
    successSurface: Color(0x1F3DD68C),
    warning: Color(0xFFF5B544),
    warningSurface: Color(0x1FF5B544),
    danger: Color(0xFFFF6B6B),
    dangerSurface: Color(0x1FFF6B6B),
    cardShadow: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 30,
        offset: Offset(0, 12),
      ),
    ],
  );

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? brand,
    Color? brandText,
    Color? brandSurface,
    Color? brandBorder,
    Color? onBrand,
    Color? success,
    Color? successSurface,
    Color? warning,
    Color? warningSurface,
    Color? danger,
    Color? dangerSurface,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? raisedShadow,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      brand: brand ?? this.brand,
      brandText: brandText ?? this.brandText,
      brandSurface: brandSurface ?? this.brandSurface,
      brandBorder: brandBorder ?? this.brandBorder,
      onBrand: onBrand ?? this.onBrand,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      danger: danger ?? this.danger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      cardShadow: cardShadow ?? this.cardShadow,
      raisedShadow: raisedShadow ?? this.raisedShadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      brand: c(brand, other.brand),
      brandText: c(brandText, other.brandText),
      brandSurface: c(brandSurface, other.brandSurface),
      brandBorder: c(brandBorder, other.brandBorder),
      onBrand: c(onBrand, other.onBrand),
      success: c(success, other.success),
      successSurface: c(successSurface, other.successSurface),
      warning: c(warning, other.warning),
      warningSurface: c(warningSurface, other.warningSurface),
      danger: c(danger, other.danger),
      dangerSurface: c(dangerSurface, other.dangerSurface),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      raisedShadow: BoxShadow.lerpList(raisedShadow, other.raisedShadow, t)!,
    );
  }
}

/// Raccourcis de lecture des jetons depuis un widget.
extension AppThemeContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  TextTheme get text => Theme.of(this).textTheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Style dédié aux montants : chiffres à chasse fixe pour que les colonnes
/// restent alignées et que les valeurs ne « dansent » pas pendant la saisie.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  /// Habillage des barres système (heure, batterie, barre de navigation)
  /// accordé au thème courant.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor:
          isDark ? AppColors.dark.canvas : AppColors.light.canvas,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }

  /// Police unique de l'application.
  ///
  /// Roboto est embarqué par Flutter sur toutes les plateformes : la fixer
  /// explicitement garantit un rendu identique sur Android et iOS, et surtout
  /// elle s'applique aussi aux thèmes de composants (boutons, barres, listes),
  /// qui n'héritent pas de la police par défaut du thème.
  static const String fontFamily = 'Roboto';

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSurface,
      onPrimaryContainer: c.brandText,
      secondary: c.brand,
      onSecondary: c.onBrand,
      error: c.danger,
      onError: brightness == Brightness.dark
          ? const Color(0xFF1B1200)
          : Colors.white,
      errorContainer: c.dangerSurface,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceMuted,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: Colors.black,
    );

    final textTheme = _textTheme(c).apply(fontFamily: fontFamily);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      textTheme: textTheme,
      primaryColor: c.brand,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlayStyle(brightness),
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: c.border),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(color: c.textSecondary, size: 22),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: c.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      // Champs de saisie : fond neutre + contour discret. L'orange n'apparaît
      // qu'au focus — un contour de marque permanent sur chaque champ est
      // précisément ce qui donnait un air « maquette » à l'application.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
          color: c.brandText,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(color: c.textMuted),
        helperMaxLines: 2,
        errorStyle: textTheme.bodySmall?.copyWith(color: c.danger),
        errorMaxLines: 2,
        prefixStyle: textTheme.bodyLarge?.copyWith(
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        border: _inputBorder(c.border),
        enabledBorder: _inputBorder(c.border),
        focusedBorder: _inputBorder(c.brand, width: 1.8),
        errorBorder: _inputBorder(c.danger),
        focusedErrorBorder: _inputBorder(c.danger, width: 1.8),
        disabledBorder: _inputBorder(c.border),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          disabledBackgroundColor: c.surfaceHover,
          disabledForegroundColor: c.textMuted,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: c.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brandText,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return brightness == Brightness.dark ? c.textMuted : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.brand;
          return c.surfaceHover;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.brand;
          return c.borderStrong;
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: Colors.transparent,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? c.surfaceHover
            : const Color(0xFF1D2430),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: c.brandText,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
      ),

      splashColor: c.brand.withValues(alpha: 0.08),
      highlightColor: c.brand.withValues(alpha: 0.05),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Échelle typographique : les titres se resserrent (letterSpacing négatif)
  /// à mesure qu'ils grossissent, ce qui est la signature visuelle des
  /// interfaces soignées ; le corps de texte reste aéré (height 1.45).
  static TextTheme _textTheme(AppColors c) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.1,
        color: c.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        height: 1.15,
        color: c.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
        color: c.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: c.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: c.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: c.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: c.textMuted,
      ),
      labelLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: c.textMuted,
      ),
    );
  }
}
