import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// =========================================================================
/// Identité visuelle des opérateurs
/// =========================================================================
/// Un seul endroit associe un libellé d'opérateur à son logo et à sa couleur.
/// Les écrans (historique, tunnel de transfert, récapitulatif) s'appuient tous
/// dessus, ce qui évite que le même opérateur apparaisse différemment d'un
/// écran à l'autre.
/// =========================================================================

/// Extrait la marque d'un libellé de la forme « MARQUE PAYS » (« MTN BJ »
/// → « MTN », « MAROC TELECOM MA » → « MAROC TELECOM »).
///
/// Indispensable : une recherche par `contains` donnait à **SAFARICOM KE** le
/// logo d'Orange, puisque « SAFARIC**OM** KE » contient « OM ». On compare
/// donc la marque entière, pas un fragment.
String operatorBrand(String label) {
  final parts = label.trim().toUpperCase().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return '';
  if (parts.length > 1 && parts.last.length == 2) parts.removeLast();
  return parts.join(' ');
}

/// Code pays à deux lettres du libellé, ou chaîne vide.
String operatorCountry(String label) {
  final parts = label.trim().toUpperCase().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.length > 1 && parts.last.length == 2) return parts.last;
  return '';
}

/// Marque → fichier de logo. La clé est la marque exacte renvoyée par
/// [operatorBrand] ; « OM » désigne Orange Money.
const Map<String, String> _brandLogos = {
  'MTN': 'assets/logos/mtn.png',
  'MOOV': 'assets/logos/moov.png',
  'CELTIS': 'assets/logos/celtis.png',
  'CELTIIS': 'assets/logos/celtis.png',
  'ORANGE': 'assets/logos/orange.png',
  'OM': 'assets/logos/orange.png',
  'WAVE': 'assets/logos/wave.png',
  'AIRTEL': 'assets/logos/airtel.svg',
  'VODAFONE': 'assets/logos/vodafone.png',
  'SAFARICOM': 'assets/logos/safaricom.png',
};

/// Couleur officielle de chaque marque, utilisée quand aucun logo n'existe :
/// les initiales sur une pastille teintée restent identifiables et voulues,
/// là où un gris uniforme donnait un rendu « champ vide ».
const Map<String, Color> _brandColors = {
  'MTN': Color(0xFFFFCC00),
  'MOOV': Color(0xFF004B93),
  'CELTIS': Color(0xFF1B3A6B),
  'CELTIIS': Color(0xFF1B3A6B),
  'ORANGE': Color(0xFFFF7900),
  'OM': Color(0xFFFF7900),
  'WAVE': Color(0xFF1DC8F2),
  'AIRTEL': Color(0xFFE40000),
  'VODAFONE': Color(0xFFE60000),
  'VODACOM': Color(0xFFE60000),
  'SAFARICOM': Color(0xFF00833E),
  'YAS': Color(0xFFE4002B),
  'TOGO': Color(0xFFE4002B),
  'TOGOCEL': Color(0xFFE4002B),
  'M-PESA': Color(0xFF00A650),
  'FREE': Color(0xFFC8102E),
  'EXPRESSO': Color(0xFF6E2B8B),
  'GLO': Color(0xFF5CB335),
  '9MOBILE': Color(0xFF006F51),
  'TELKOM': Color(0xFF0057B8),
  'CELL C': Color(0xFF000000),
  'INWI': Color(0xFF8E2A8B),
  'IAM': Color(0xFF004B93),
  'MAROC TELECOM': Color(0xFF004B93),
};

String? operatorLogoAsset(String label) => _brandLogos[operatorBrand(label)];

Color operatorColor(String label) =>
    _brandColors[operatorBrand(label)] ?? const Color(0xFF6B7280);

/// Initiales de repli (3 caractères maximum, lisibles dans une pastille).
String operatorInitials(String label) {
  final brand = operatorBrand(label);
  if (brand.isEmpty) return '?';
  final words = brand.split(' ');
  if (words.length > 1) {
    return words.take(2).map((w) => w.characters.first).join();
  }
  return brand.length <= 3 ? brand : brand.substring(0, 3);
}

/// Pastille ronde d'un opérateur.
///
/// Le logo est posé sur un disque **blanc dans les deux thèmes** : les logos
/// des opérateurs sont dessinés pour un fond clair, et un disque blanc les
/// fait lire comme une vignette assumée plutôt que comme une image mal
/// détourée. Le `ClipOval` évite que les logos carrés débordent.
class OperatorAvatar extends StatelessWidget {
  final String label;
  final double size;

  /// URL de secours fournie par le serveur si aucun asset local ne correspond.
  final String? fallbackUrl;

  const OperatorAvatar({
    super.key,
    required this.label,
    this.size = 40,
    this.fallbackUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final asset = operatorLogoAsset(label);
    final remote = asset == null ? fallbackUrl : null;
    final hasImage = asset != null || (remote != null && remote.isNotEmpty);
    final brandColor = operatorColor(label);

    Widget content;
    if (asset != null && asset.toLowerCase().endsWith('.svg')) {
      // Les SVG sont transparents : on les pose sur le disque blanc avec une
      // marge, plutôt que de les étirer jusqu'aux bords.
      content = Padding(
        padding: EdgeInsets.all(size * 0.18),
        child: SvgPicture.asset(asset, fit: BoxFit.contain),
      );
    } else if (asset != null) {
      // Les PNG sont normalisés en carrés dont le fond va jusqu'aux bords :
      // `cover` remplit donc le cercle entièrement, ce qui donne une vignette
      // pleine et non un carré inscrit dans un disque.
      content = SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _Initials(label: label, size: size),
        ),
      );
    } else if (remote != null && remote.isNotEmpty) {
      content = Image.network(
        remote,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _Initials(label: label, size: size),
      );
    } else {
      content = _Initials(label: label, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Disque blanc sous un logo ; pastille teintée sous des initiales.
        color: hasImage
            ? Colors.white
            : Color.alphaBlend(brandColor.withValues(alpha: 0.14), c.surface),
        shape: BoxShape.circle,
        border: Border.all(
          color: hasImage ? c.border : brandColor.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: content),
    );
  }
}

class _Initials extends StatelessWidget {
  final String label;
  final double size;

  const _Initials({required this.label, required this.size});

  @override
  Widget build(BuildContext context) {
    final brandColor = operatorColor(label);
    // Assombrit la couleur de marque au besoin pour rester lisible en clair.
    final isDark = context.isDark;
    final text = isDark
        ? Color.alphaBlend(brandColor.withValues(alpha: 0.85), Colors.white)
        : HSLColor.fromColor(brandColor)
            .withLightness(
                (HSLColor.fromColor(brandColor).lightness * 0.62).clamp(0.0, 0.42))
            .toColor();

    return Text(
      operatorInitials(label),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size * 0.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: text,
      ),
    );
  }
}

/// Les deux opérateurs d'un transfert, en pastilles superposées.
///
/// La superposition dit « ces deux-là vont ensemble » en occupant moins de
/// place que deux pastilles séparées par une flèche.
class OperatorPair extends StatelessWidget {
  final String from;
  final String to;
  final double size;
  final String? fromLogoUrl;
  final String? toLogoUrl;

  const OperatorPair({
    super.key,
    required this.from,
    required this.to,
    this.size = 40,
    this.fromLogoUrl,
    this.toLogoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final overlap = size * 0.34;
    return SizedBox(
      width: size * 2 - overlap,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: OperatorAvatar(label: from, size: size, fallbackUrl: fromLogoUrl),
          ),
          Positioned(
            left: size - overlap,
            child: Container(
              // Léger liseré à la couleur du fond : détache la pastille de
              // devant de celle de derrière, quel que soit le thème.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.surface, width: 2),
              ),
              child: OperatorAvatar(label: to, size: size, fallbackUrl: toLogoUrl),
            ),
          ),
        ],
      ),
    );
  }
}
