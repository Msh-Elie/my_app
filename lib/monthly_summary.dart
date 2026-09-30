import 'package:flutter/material.dart';

import 'history_page.dart' show parseHistoryDate;
import 'history_storage.dart';
import 'theme.dart';
import 'ui_kit.dart';

/// Activité du mois en cours, telle qu'affichée sur l'accueil.
class MonthlyStats {
  /// Nombre de transferts validés ce mois-ci.
  final int transferCount;

  /// Somme envoyée, ou `null` si plusieurs devises se mélangent — additionner
  /// des XOF et des KES donnerait un nombre qui ne veut rien dire.
  final double? total;

  /// Devise de [total] ; vide quand [total] est `null`.
  final String currency;

  const MonthlyStats({
    required this.transferCount,
    this.total,
    this.currency = '',
  });

  static const empty = MonthlyStats(transferCount: 0);

  bool get isEmpty => transferCount == 0;
}

/// Sépare « 25000 XOF » en sa valeur et sa devise.
///
/// Tolère les séparateurs de milliers déjà posés (espaces fines insécables
/// comprises) : l'historique local et celui du serveur ne formatent pas
/// forcément de la même façon.
({double value, String currency})? parseAmount(String raw) {
  final match = RegExp(r'^\s*([\d\s\u00A0\u202F.,]+?)\s*([A-Za-z]*)\s*$')
      .firstMatch(raw);
  if (match == null) return null;

  final digits = match.group(1)!.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return null;

  final value = double.tryParse(digits);
  if (value == null) return null;

  return (value: value, currency: match.group(2)!.toUpperCase());
}

/// Calcule l'activité du mois de [now] à partir de l'historique local.
///
/// Seuls les transferts **validés** comptent : afficher un montant « envoyé »
/// qui inclurait des échecs serait faux.
MonthlyStats computeMonthlyStats(List<HistoryRecord> records, {DateTime? now}) {
  final today = now ?? DateTime.now();

  final amounts = <({double value, String currency})>[];
  for (final record in records) {
    if (record.status.toLowerCase() != 'valide') continue;

    final date = parseHistoryDate(record.date);
    if (date == null) continue;
    if (date.year != today.year || date.month != today.month) continue;

    final parsed = parseAmount(record.amount);
    if (parsed != null) amounts.add(parsed);
  }

  if (amounts.isEmpty) return MonthlyStats.empty;

  final currencies = amounts.map((a) => a.currency).toSet();
  if (currencies.length != 1) {
    // Devises mêlées : on annonce le nombre, pas une somme trompeuse.
    return MonthlyStats(transferCount: amounts.length);
  }

  return MonthlyStats(
    transferCount: amounts.length,
    total: amounts.fold<double>(0, (sum, a) => sum + a.value),
    currency: currencies.first,
  );
}

/// Bandeau d'activité affiché en tête du tunnel de transfert.
///
/// L'accueil n'affichait jusqu'ici qu'un formulaire vide : ce bandeau lui
/// donne un contenu propre à l'utilisateur, et rend l'application vivante dès
/// la première seconde. Il disparaît dès qu'un transfert est en cours, pour
/// ne pas concurrencer l'étape à remplir.
class MonthlySummaryCard extends StatelessWidget {
  final MonthlyStats stats;
  final VoidCallback? onTap;

  const MonthlySummaryCard({super.key, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8D42), Color(0xFFF05A00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: kBrand.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ENVOYÉ CE MOIS',
                    style: context.text.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    stats.total == null
                        ? '${stats.transferCount} transferts'
                        : '${formatThousands(stats.total!.toStringAsFixed(0))}'
                            '$noBreakSpace${stats.currency}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  if (stats.total != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stats.transferCount == 1
                          ? '1 transfert validé'
                          : '${stats.transferCount} transferts validés',
                      style: context.text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.trending_up_rounded,
                  color: c.onBrand, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
