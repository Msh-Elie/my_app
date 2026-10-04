import 'package:flutter/material.dart';

import 'history_storage.dart';
import 'operators.dart';
import 'theme.dart';
import 'ui_kit.dart';

/// Un couple d'opérateurs déjà emprunté (« MTN BJ → MOOV BJ »).
class TransferRoute {
  final String from;
  final String to;

  const TransferRoute({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      other is TransferRoute && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Les trajets récemment utilisés, du plus récent au plus ancien.
///
/// L'historique est déjà classé par date décroissante : on se contente de le
/// parcourir en écartant les doublons, ce qui fait remonter naturellement les
/// trajets habituels.
List<TransferRoute> recentRoutes(
  List<HistoryRecord> history, {
  int limit = 4,
}) {
  final seen = <TransferRoute>{};
  final routes = <TransferRoute>[];

  for (final record in history) {
    if (record.from.isEmpty || record.to.isEmpty) continue;
    final route = TransferRoute(from: record.from, to: record.to);
    if (!seen.add(route)) continue;
    routes.add(route);
    if (routes.length >= limit) break;
  }

  return routes;
}

/// Bande de raccourcis vers les trajets déjà empruntés.
///
/// Refaire le même transfert est le geste le plus courant : le proposer d'un
/// tap évite de reparcourir deux fois la liste des opérateurs. Accessoirement,
/// cette bande occupe la place laissée vide sous les deux cartes.
class RecentRoutesStrip extends StatelessWidget {
  final List<TransferRoute> routes;
  final void Function(TransferRoute route) onSelected;

  const RecentRoutesStrip({
    super.key,
    required this.routes,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Trajets récents'),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final route = routes[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(route),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OperatorPair(from: route.from, to: route.to, size: 28),
                      const SizedBox(width: AppSpacing.sm),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: operatorBrand(route.from)),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.arrow_forward_rounded,
                                    size: 12, color: c.textMuted),
                              ),
                            ),
                            TextSpan(text: operatorBrand(route.to)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium
                            ?.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Repère affiché tant qu'aucun transfert n'a encore été fait.
///
/// Sans lui, la première étape se résume à deux cartes et une grande surface
/// vide : rien n'indique ce qui attend l'utilisateur, ni combien de temps cela
/// prendra. Il disparaît dès le premier trajet enregistré.
class HowItWorksCard extends StatelessWidget {
  const HowItWorksCard({super.key});

  static const _steps = [
    (icon: Icons.swap_horiz_rounded, text: 'Choisissez les deux opérateurs'),
    (icon: Icons.dialpad_rounded, text: 'Saisissez les numéros'),
    (icon: Icons.verified_rounded, text: 'Vérifiez le montant, puis validez'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Comment ça marche'),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.brandSurface,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: context.text.labelSmall?.copyWith(
                          color: c.brandText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _steps[i].text,
                        style: context.text.bodyMedium
                            ?.copyWith(color: c.textPrimary),
                      ),
                    ),
                    Icon(_steps[i].icon, size: 18, color: c.textMuted),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
