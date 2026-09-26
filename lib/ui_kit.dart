import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// =========================================================================
/// Briques d'interface partagées
/// =========================================================================
/// Chaque écran réutilise ces composants au lieu de redessiner ses propres
/// cartes, puces et boutons. C'est ce qui fait qu'une application « se tient »
/// visuellement : un seul rayon de carte, une seule hauteur de bouton, une
/// seule façon d'afficher un statut.
/// =========================================================================

/// Espace fine insecable (U+202F) : separateur de milliers en francais.
/// Ecrite en echappement, car a l'oeil nu elle est indistinguable d'une
/// espace ordinaire — dans le code comme dans les tests.
const String narrowNoBreakSpace = '\u202F';

/// Espace insecable (U+00A0), placee avant le symbole monetaire pour qu'il
/// ne soit jamais rejete seul a la ligne suivante.
const String noBreakSpace = '\u00A0';

/// Groupe les chiffres par tranches de trois, séparées par une espace fine
/// insécable — la convention française (« 120 000 » et non « 120000 »).
///
/// L'espace est insécable pour qu'un montant ne soit jamais coupé en fin de
/// ligne, et fine pour ne pas disloquer le nombre.
String formatThousands(String digits) {
  final clean = digits.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.length < 4) return clean;
  final buffer = StringBuffer();
  for (var i = 0; i < clean.length; i++) {
    if (i > 0 && (clean.length - i) % 3 == 0) buffer.write(narrowNoBreakSpace);
    buffer.write(clean[i]);
  }
  return buffer.toString();
}

/// Met en forme un montant stocké sous la forme « 25000 XOF ».
/// Les valeurs inattendues sont renvoyées telles quelles.
String formatAmountLabel(String raw) {
  final match = RegExp(r'^\s*(\d+)(?:[.,](\d+))?\s*(.*)$').firstMatch(raw);
  if (match == null) return raw;
  final integer = formatThousands(match.group(1)!);
  final decimals = match.group(2);
  final suffix = match.group(3)?.trim() ?? '';
  final number = decimals == null ? integer : '$integer,$decimals';
  return suffix.isEmpty ? number : '$number$noBreakSpace$suffix';
}

/// Intention de couleur d'un élément de statut.
enum Tone { neutral, brand, success, warning, danger }

extension ToneColors on Tone {
  Color foreground(BuildContext context) {
    final c = context.colors;
    return switch (this) {
      Tone.neutral => c.textSecondary,
      Tone.brand => c.brandText,
      Tone.success => c.success,
      Tone.warning => c.warning,
      Tone.danger => c.danger,
    };
  }

  Color background(BuildContext context) {
    final c = context.colors;
    return switch (this) {
      Tone.neutral => c.surfaceMuted,
      Tone.brand => c.brandSurface,
      Tone.success => c.successSurface,
      Tone.warning => c.warningSurface,
      Tone.danger => c.dangerSurface,
    };
  }
}

/// Carte standard : surface, contour discret, ombre douce, rayon constant.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Met la carte en avant (contour de marque + ombre plus marquée).
  final bool highlighted;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: highlighted ? c.brandBorder : c.border),
        boxShadow: highlighted ? c.raisedShadow : c.cardShadow,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: content,
      ),
    );
  }
}

/// Titre de section en petites capitales, au-dessus d'un groupe de réglages.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(text.toUpperCase(), style: context.text.labelSmall),
    );
  }
}

/// Puce de statut (« Nom vérifié », « En cours », « Échec »…).
class StatusPill extends StatelessWidget {
  final String label;
  final Tone tone;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: fg,
              letterSpacing: 0.1,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encart d'information / d'avertissement.
class InfoBanner extends StatelessWidget {
  final String message;
  final Tone tone;
  final IconData icon;

  const InfoBanner({
    super.key,
    required this.message,
    this.tone = Tone.brand,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(color: fg, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton principal : hauteur et rayon constants, état de chargement intégré.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onBrand),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}

/// Indicateur d'avancement du tunnel de transfert.
///
/// Une barre segmentée qui se remplit étape par étape : l'utilisateur sait
/// toujours où il en est et combien il reste. Son absence était l'un des
/// principaux points qui faisaient « prototype ».
class StepProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> labels;

  const StepProgress({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.labels = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = currentStep < labels.length ? labels[currentStep] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(totalSteps, (i) {
            final done = i <= currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  height: 4,
                  decoration: BoxDecoration(
                    color: done ? c.brand : c.surfaceHover,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            );
          }),
        ),
        if (label != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Étape ${currentStep + 1} sur $totalSteps',
                style: context.text.labelSmall,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: c.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Ligne « libellé → valeur » d'un récapitulatif.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final bool allowWrap;

  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.allowWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: allowWrap ? 3 : 1,
              overflow: allowWrap ? TextOverflow.visible : TextOverflow.ellipsis,
              softWrap: allowWrap,
              style: (emphasize
                      ? context.text.titleMedium
                      : context.text.bodyLarge)
                  ?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
                fontFeatures: kTabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloc d'en-tête d'un écran secondaire : gros titre + sous-titre.
class PageHeading extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PageHeading({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: context.text.bodyMedium),
        ],
      ],
    );
  }
}

/// Coche de validation qui se trace sous les yeux de l'utilisateur.
///
/// Un transfert validé est le moment qui compte : le cercle se referme, puis
/// la coche s'écrit. Le mouvement dure moins d'une seconde et ne se répète
/// pas — il marque l'instant sans faire attendre.
class AnimatedCheck extends StatefulWidget {
  final double size;
  final Color color;
  final Color background;

  const AnimatedCheck({
    super.key,
    required this.size,
    required this.color,
    required this.background,
  });

  @override
  State<AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CheckPainter(
          progress: _controller.value,
          color: widget.color,
          background: widget.background,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color background;

  const _CheckPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = s / 2;

    canvas.drawCircle(center, radius, Paint()..color = background);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Phase 1 — l'anneau se referme.
    final ringProgress = Curves.easeOutCubic.transform(
      (progress / 0.55).clamp(0.0, 1.0),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - stroke.strokeWidth / 2),
      -math.pi / 2,
      2 * math.pi * ringProgress,
      false,
      stroke,
    );

    // Phase 2 — la coche s'écrit, en partant du creux vers la pointe haute.
    final checkProgress = Curves.easeOutCubic.transform(
      ((progress - 0.45) / 0.55).clamp(0.0, 1.0),
    );
    if (checkProgress <= 0) return;

    final path = Path()
      ..moveTo(center.dx - s * 0.20, center.dy + s * 0.01)
      ..lineTo(center.dx - s * 0.05, center.dy + s * 0.15)
      ..lineTo(center.dx + s * 0.21, center.dy - s * 0.14);

    // PathMetrics permet de n'extraire que la portion déjà « écrite ».
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkProgress),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}

/// Montant dont la valeur glisse d'un chiffre à l'autre.
///
/// Quand les frais changent le net à recevoir, un saut brutal se remarque à
/// peine ; un défilement rapide attire l'œil sur ce qui vient de bouger.
class AnimatedAmount extends StatelessWidget {
  final double value;
  final String currency;
  final TextStyle? style;

  const AnimatedAmount({
    super.key,
    required this.value,
    required this.currency,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value, end: value),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(
        '${formatThousands(animated.round().toString())}$noBreakSpace$currency',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (style ?? context.text.titleLarge)
            ?.copyWith(fontFeatures: kTabularFigures),
      ),
    );
  }
}

/// Dessine le symbole de la marque : deux flèches horizontales opposées —
/// l'icône « données mobiles » d'Android, couchée.
///
/// Tracé en code plutôt qu'importé en image, pour que la marque affichée dans
/// l'application soit rigoureusement la même que l'icône de lancement : mêmes
/// proportions, et une netteté parfaite à toute taille.
class BrandGlyphPainter extends CustomPainter {
  final Color color;

  const BrandGlyphPainter({required this.color});

  // Proportions reprises du générateur d'icône (rapportées à un carré de 1).
  static const _span = 0.488;
  static const _gap = 0.191;
  static const _thickness = 0.0703;
  static const _headLength = 0.1133;
  static const _headHalf = 0.084;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..color = color;

    void arrow({required double y, required bool toRight}) {
      final half = _span * s / 2;
      final tip = toRight ? cx + half : cx - half;
      final tail = toRight ? cx - half : cx + half;
      final dir = toRight ? 1.0 : -1.0;
      final base = tip - dir * _headLength * s;

      // Hampe à bouts arrondis, prolongée sous la pointe pour éviter
      // toute encoche à la jonction.
      final shaftEnd = tip - dir * _headLength * s * 0.72;
      final rect = Rect.fromLTRB(
        math.min(tail, shaftEnd),
        y - _thickness * s / 2,
        math.max(tail, shaftEnd),
        y + _thickness * s / 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(_thickness * s / 2)),
        paint,
      );

      canvas.drawPath(
        Path()
          ..moveTo(base, y - _headHalf * s)
          ..lineTo(base, y + _headHalf * s)
          ..lineTo(tip, y)
          ..close(),
        paint,
      );
    }

    arrow(y: cy - _gap * s / 2, toRight: true);
    arrow(y: cy + _gap * s / 2, toRight: false);
  }

  @override
  bool shouldRepaint(BrandGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Signature visuelle de l'application (pastille orange + nom).
class BrandMark extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const BrandMark({super.key, this.size = 40, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8D42), Color(0xFFFA6400)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                color: kBrand.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: CustomPaint(
            painter: const BrandGlyphPainter(color: Colors.white),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(width: size * 0.3),
          Text(
            'SwitchMoney',
            style: context.text.titleLarge?.copyWith(
              fontSize: size * 0.45,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Affiche un message temporaire accordé au thème.
///
/// Remplace les `SnackBar(backgroundColor: Colors.red)` dispersés dans le
/// code : une seule présentation, avec une icône qui porte le sens.
void showAppSnack(
  BuildContext context,
  String message, {
  Tone tone = Tone.neutral,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showSnackOn(messenger, message, tone: tone, duration: duration);
}

/// Variante prenant directement le messenger.
///
/// Utile dans les fonctions asynchrones : le messenger est capturé avant le
/// premier `await`, ce qui évite d'utiliser un `BuildContext` devenu invalide.
void showSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  Tone tone = Tone.neutral,
  Duration duration = const Duration(seconds: 4),
}) {
  final icon = switch (tone) {
    Tone.success => Icons.check_circle_rounded,
    Tone.danger => Icons.error_rounded,
    Tone.warning => Icons.warning_amber_rounded,
    _ => Icons.info_rounded,
  };
  final accent = switch (tone) {
    Tone.success => const Color(0xFF3DD68C),
    Tone.danger => const Color(0xFFFF7B7B),
    Tone.warning => const Color(0xFFF5B544),
    Tone.brand => const Color(0xFFFF9048),
    Tone.neutral => Colors.white70,
  };

  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        content: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
