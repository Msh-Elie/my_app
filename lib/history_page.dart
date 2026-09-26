import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'history_storage.dart';
import 'operators.dart';
import 'theme.dart';
import 'ui_kit.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: HistoryContent(embedded: false)),
    );
  }
}

class HistoryContent extends StatefulWidget {
  final bool embedded;

  const HistoryContent({super.key, required this.embedded});

  @override
  State<HistoryContent> createState() => _HistoryContentState();
}

class _HistoryContentState extends State<HistoryContent> {
  int selectedStatus = 0; // 0 = tout, 1 = valide, 2 = en_cours, 3 = echec
  bool loading = true;

  List<HistoryRecord> persisted = const [];

  String _normalizeUiStatus(String? status, String? rawStatus) {
    final s = (status ?? '').trim().toLowerCase();
    final r = (rawStatus ?? '').trim().toUpperCase();

    if (s == 'valide') return 'valide';
    if (r == 'SUCCESS' || r == 'COMPLETED' || r == 'DUPLICATE_IGNORED') {
      return 'valide';
    }

    if (s == 'echec' || s == 'failed' || s == 'error') return 'echec';
    if (r == 'FAILED' || r == 'ERROR' || r == 'REJECTED' || r == 'CANCELLED') {
      return 'echec';
    }

    return 'en_cours';
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final resp = await ApiClient.instance
          .getJson('/api/history?limit=80', timeout: kColdStartTimeout);

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final rawItems =
            (decoded is Map<String, dynamic>) ? decoded['items'] : null;
        if (rawItems is List) {
          final fromApi = rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => HistoryRecord(
                  id: e['id']?.toString() ?? '',
                  from: e['from']?.toString() ?? '',
                  to: e['to']?.toString() ?? '',
                  amount: e['amount']?.toString() ?? '',
                  status: _normalizeUiStatus(
                    e['status']?.toString(),
                    e['rawStatus']?.toString(),
                  ),
                  date: e['date']?.toString() ?? '',
                  fromLogo: e['fromLogo']?.toString(),
                  toLogo: e['toLogo']?.toString(),
                ),
              )
              .toList();

          if (!mounted) return;
          setState(() {
            persisted = fromApi;
            loading = false;
          });
          return;
        }
      }
    } catch (_) {
      // backend indisponible : repli sur l'historique local
    }

    final stored = await HistoryStorage.load();
    if (!mounted) return;
    setState(() {
      persisted = stored;
      loading = false;
    });
  }

  List<HistoryRecord> get _visibleEntries {
    if (selectedStatus == 0) return persisted;
    final wanted = switch (selectedStatus) {
      1 => 'valide',
      3 => 'echec',
      _ => 'en_cours',
    };
    return persisted.where((e) => e.status.toLowerCase() == wanted).toList();
  }

  int _countFor(int filter) {
    if (filter == 0) return persisted.length;
    final wanted = switch (filter) {
      1 => 'valide',
      3 => 'echec',
      _ => 'en_cours',
    };
    return persisted.where((e) => e.status.toLowerCase() == wanted).length;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.embedded ? AppSpacing.md : AppSpacing.lg;
    final groups = groupByDay(_visibleEntries);

    return Column(
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 26),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Historique',
                    textAlign: TextAlign.center,
                    style: context.text.titleLarge,
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),

        // Filtres par statut
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            widget.embedded ? AppSpacing.sm : 0,
            horizontal,
            AppSpacing.md,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (index, label) in const [
                  (0, 'Tout'),
                  (1, 'Validé'),
                  (2, 'En cours'),
                  (3, 'Échec'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _FilterChip(
                      label: label,
                      count: _countFor(index),
                      active: selectedStatus == index,
                      onTap: () => setState(() => selectedStatus = index),
                    ),
                  ),
              ],
            ),
          ),
        ),

        Expanded(
          child: loading
              ? _HistorySkeleton(horizontal: horizontal)
              : groups.isEmpty
                  ? _EmptyState(filtered: selectedStatus != 0)
                  : RefreshIndicator(
                      color: context.colors.brand,
                      onRefresh: _loadHistory,
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          AppSpacing.xs,
                          horizontal,
                          AppSpacing.xl,
                        ),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: index == 0 ? 0 : AppSpacing.lg,
                                  bottom: AppSpacing.sm,
                                  left: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Text(group.label.toUpperCase(),
                                        style: context.text.labelSmall),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Divider(
                                          height: 1, color: context.colors.border),
                                    ),
                                  ],
                                ),
                              ),
                              for (final item in group.items)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: _HistoryCard(item: item),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

/// Un paquet d'opérations partageant le même jour.
class HistoryGroup {
  final String label;
  final List<HistoryRecord> items;

  const HistoryGroup(this.label, this.items);
}

/// Date stockée au format `jj/mm/aaaa` (voir HistoryStorage.formatDisplayDate).
DateTime? parseHistoryDate(String raw) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(raw.trim());
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Libellé relatif d'un jour : « Aujourd'hui », « Hier », sinon la date en
/// toutes lettres. Repérer une opération récente devient immédiat.
String dayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;

  if (diff == 0) return 'Aujourd\'hui';
  if (diff == 1) return 'Hier';
  final month = _months[day.month - 1];
  return day.year == today.year
      ? '${day.day} $month'
      : '${day.day} $month ${day.year}';
}

/// Regroupe les opérations par jour, les plus récentes d'abord. Les dates
/// illisibles sont rassemblées à la fin plutôt que masquées.
List<HistoryGroup> groupByDay(List<HistoryRecord> items, {DateTime? now}) {
  final byDay = <DateTime, List<HistoryRecord>>{};
  final undated = <HistoryRecord>[];

  for (final item in items) {
    final date = parseHistoryDate(item.date);
    if (date == null) {
      undated.add(item);
    } else {
      byDay.putIfAbsent(date, () => []).add(item);
    }
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  final groups = [
    for (final day in days) HistoryGroup(dayLabel(day, now: now), byDay[day]!),
  ];
  if (undated.isNotEmpty) groups.add(HistoryGroup('Autres', undated));
  return groups;
}

/// Filtre avec compteur : on voit d'un coup d'œil combien d'opérations
/// tombent dans chaque état.
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: active ? c.brandSurface : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: active ? c.brandBorder : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: active ? c.brandText : c.textSecondary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: context.text.labelMedium?.copyWith(
                  color: active ? c.brandText : c.textMuted,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Esquisse affichée pendant le chargement : la page garde sa forme au lieu
/// de sauter d'un indicateur centré à une liste pleine.
class _HistorySkeleton extends StatelessWidget {
  final double horizontal;

  const _HistorySkeleton({required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: c.surfaceHover,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(horizontal, AppSpacing.xs, horizontal, 0),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 34,
              decoration: BoxDecoration(
                color: c.surfaceHover,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(120, 12),
                  const SizedBox(height: 8),
                  bar(70, 10),
                ],
              ),
            ),
            bar(64, 14),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;

  const _EmptyState({required this.filtered});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(Icons.receipt_long_rounded,
                  size: 28, color: c.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              filtered ? 'Aucune opération ici' : 'Pas encore de transfert',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              filtered
                  ? 'Essayez un autre filtre pour voir vos opérations.'
                  : 'Vos transferts apparaîtront ici une fois effectués.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

Tone toneForStatus(String status) => switch (status.toLowerCase()) {
      'valide' => Tone.success,
      'echec' => Tone.danger,
      _ => Tone.warning,
    };

String labelForStatus(String status) => switch (status.toLowerCase()) {
      'valide' => 'Validé',
      'echec' => 'Échec',
      _ => 'En cours',
    };

IconData iconForStatus(String status) => switch (status.toLowerCase()) {
      'valide' => Icons.check_rounded,
      'echec' => Icons.close_rounded,
      _ => Icons.schedule_rounded,
    };

class _HistoryCard extends StatelessWidget {
  final HistoryRecord item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      onTap: () => _showDetails(context, item),
      child: Row(
        children: [
          OperatorPair(
            from: item.from,
            to: item.to,
            size: 36,
            fromLogoUrl: item.fromLogo,
            toLogoUrl: item.toLogo,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Un seul bloc de texte plutôt que deux `Flexible` côte à
                // côte : ces derniers se partageaient la largeur à parts
                // égales et tronquaient « ORANGE » alors que « WAVE »
                // laissait de la place. La flèche est une icône et non le
                // caractère « → », que certaines polices ne dessinent pas.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: operatorBrand(item.from)),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 13, color: c.textMuted),
                        ),
                      ),
                      TextSpan(text: operatorBrand(item.to)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 5),
                StatusPill(
                  label: labelForStatus(item.status),
                  tone: toneForStatus(item.status),
                  icon: iconForStatus(item.status),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            formatAmountLabel(item.amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fiche détaillée d'une opération.
///
/// La référence et la date vivent ici plutôt que dans la liste : chaque ligne
/// reste lisible, et l'information complète reste à un tap.
void _showDetails(BuildContext context, HistoryRecord item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      final tone = toneForStatus(item.status);

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: OperatorPair(from: item.from, to: item.to, size: 52),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                formatAmountLabel(item.amount),
                textAlign: TextAlign.center,
                style: sheetContext.text.displaySmall
                    ?.copyWith(fontFeatures: kTabularFigures),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: StatusPill(
                  label: labelForStatus(item.status),
                  tone: tone,
                  icon: iconForStatus(item.status),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Column(
                  children: [
                    DetailRow(label: 'Depuis', value: item.from),
                    DetailRow(label: 'Vers', value: item.to),
                    DetailRow(label: 'Date', value: item.date),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Référence de l\'opération',
                        style: sheetContext.text.labelSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            item.id.isEmpty ? '—' : item.id,
                            style: sheetContext.text.bodySmall?.copyWith(
                              color: c.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (item.id.isNotEmpty)
                          IconButton(
                            tooltip: 'Copier la référence',
                            icon: Icon(Icons.copy_rounded,
                                size: 18, color: c.textMuted),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: item.id));
                              showAppSnack(sheetContext, 'Référence copiée',
                                  tone: Tone.success);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
