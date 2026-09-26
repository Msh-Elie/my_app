import 'package:flutter/material.dart';

import 'operators.dart';
import 'theme.dart';

/// =========================================================================
/// Choix des opérateurs
/// =========================================================================
/// Remplace les deux roues de sélection côte à côte. Une roue oblige à faire
/// défiler une liste de trente opérateurs sans pouvoir chercher, ne montre
/// que trois entrées à la fois et n'a aucun moyen d'indiquer qu'un opérateur
/// est indisponible. Ici : deux cartes qui affichent le choix courant, un
/// bouton d'inversion, et une feuille de sélection avec recherche et
/// regroupement par pays.
/// =========================================================================

/// Ce que le sélecteur doit savoir d'un opérateur pour l'afficher.
class OperatorOption {
  final String label;
  final String prefix;

  /// Faux quand l'opérateur ne peut pas assurer le sens demandé.
  final bool available;

  /// Raison affichée à côté d'un opérateur indisponible.
  final String? unavailableReason;

  const OperatorOption({
    required this.label,
    required this.prefix,
    this.available = true,
    this.unavailableReason,
  });
}

/// Carte « Depuis » / « Vers » : logo, nom, pays, indicatif.
class OperatorSelectorCard extends StatelessWidget {
  final String caption;
  final String label;
  final String prefix;
  final VoidCallback onTap;

  /// Signale un opérateur qui ne peut pas assurer ce sens de transfert.
  final String? warning;

  const OperatorSelectorCard({
    super.key,
    required this.caption,
    required this.label,
    required this.prefix,
    required this.onTap,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocked = warning != null;

    return _PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: blocked ? c.warning : c.border),
          boxShadow: c.cardShadow,
        ),
        child: Row(
          children: [
            OperatorAvatar(label: label, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caption.toUpperCase(), style: context.text.labelSmall),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${operatorCountryName(label)} · $prefix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.unfold_more_rounded, size: 20, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Bouton d'inversion du sens du transfert.
///
/// Il pivote d'un demi-tour à chaque appui : le mouvement dit ce qui vient de
/// se produire, là où un simple échange de textes passerait inaperçu.
class SwapDirectionButton extends StatefulWidget {
  final VoidCallback onSwap;

  const SwapDirectionButton({super.key, required this.onSwap});

  @override
  State<SwapDirectionButton> createState() => _SwapDirectionButtonState();
}

class _SwapDirectionButtonState extends State<SwapDirectionButton> {
  int _turns = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _PressableScale(
      onTap: () {
        setState(() => _turns++);
        widget.onSwap();
      },
      child: AnimatedRotation(
        turns: _turns / 2,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
            boxShadow: c.cardShadow,
          ),
          child: Icon(Icons.swap_vert_rounded, size: 22, color: c.brandText),
        ),
      ),
    );
  }
}

/// Réduit légèrement son enfant pendant l'appui : la cible réagit au doigt.
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressableScale({required this.child, required this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Ouvre la feuille de sélection et renvoie l'opérateur choisi, ou `null`.
Future<String?> showOperatorPicker(
  BuildContext context, {
  required String title,
  required String selected,
  required List<OperatorOption> options,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _OperatorPickerSheet(
      title: title,
      selected: selected,
      options: options,
    ),
  );
}

class _OperatorPickerSheet extends StatefulWidget {
  final String title;
  final String selected;
  final List<OperatorOption> options;

  const _OperatorPickerSheet({
    required this.title,
    required this.selected,
    required this.options,
  });

  @override
  State<_OperatorPickerSheet> createState() => _OperatorPickerSheetState();
}

class _OperatorPickerSheetState extends State<_OperatorPickerSheet>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final AnimationController _entrance;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entrance.dispose();
    super.dispose();
  }

  /// Recherche tolérante : sur le nom, le pays ou l'indicatif, sans tenir
  /// compte de la casse, des espaces superflus ni des accents — taper
  /// « benin » ou « cote » doit suffire.
  bool _matches(OperatorOption option) {
    if (_query.trim().isEmpty) return true;
    final q = foldAccents(_query.trim());
    return foldAccents(option.label).contains(q) ||
        foldAccents(operatorCountryName(option.label)).contains(q) ||
        option.prefix.contains(q);
  }

  /// Opérateurs groupés par pays.
  ///
  /// Le pays de l'opérateur déjà sélectionné passe en tête — c'est celui que
  /// l'on consulte le plus souvent. Les autres suivent par ordre alphabétique
  /// français : le tri ignore les accents, sinon « Burkina Faso » précéderait
  /// « Bénin », 'u' passant avant 'é' dans l'ordre des codes de caractères.
  List<MapEntry<String, List<OperatorOption>>> get _grouped {
    final visible = widget.options.where(_matches).toList();
    final byCountry = <String, List<OperatorOption>>{};
    for (final option in visible) {
      byCountry.putIfAbsent(operatorCountryName(option.label), () => []).add(option);
    }

    final pinned = operatorCountryName(widget.selected);
    final entries = byCountry.entries.toList()
      ..sort((a, b) {
        if (a.key == pinned) return -1;
        if (b.key == pinned) return 1;
        return foldAccents(a.key).compareTo(foldAccents(b.key));
      });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = _grouped;

    // La feuille occupe une hauteur fixe : la liste ne doit pas « sauter »
    // quand la recherche réduit le nombre de résultats.
    final height = MediaQuery.sizeOf(context).height * 0.82;

    var rowIndex = 0;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _searchController,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    style: context.text.bodyLarge,
                    cursorColor: c.brand,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un opérateur, un pays',
                      prefixIcon:
                          Icon(Icons.search_rounded, size: 20, color: c.textMuted),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: c.textMuted),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? _NoResult(query: _query)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.xl,
                                AppSpacing.md,
                                AppSpacing.xl,
                                AppSpacing.xs,
                              ),
                              child: Text(group.key.toUpperCase(),
                                  style: context.text.labelSmall),
                            ),
                            for (final option in group.value)
                              _StaggeredIn(
                                controller: _entrance,
                                index: rowIndex++,
                                child: _OperatorRow(
                                  option: option,
                                  selected: option.label == widget.selected,
                                  onTap: option.available
                                      ? () => Navigator.pop(context, option.label)
                                      : null,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fait apparaître son enfant avec un léger décalage selon sa position.
///
/// L'effet d'escalier donne à la liste une entrée vivante ; au-delà de la
/// douzaine d'éléments le décalage est plafonné, sinon le bas de la liste
/// se ferait attendre.
class _StaggeredIn extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Widget child;

  const _StaggeredIn({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index.clamp(0, 12) * 0.045).clamp(0.0, 0.55);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.45).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - animation.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class _OperatorRow extends StatelessWidget {
  final OperatorOption option;
  final bool selected;
  final VoidCallback? onTap;

  const _OperatorRow({
    required this.option,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            color: selected ? c.brandSurface : Colors.transparent,
            child: Row(
              children: [
                OperatorAvatar(label: option.label, size: 38),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        disabled
                            ? (option.unavailableReason ?? 'Indisponible')
                            : option.prefix,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: disabled ? c.warning : c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: c.brandText)
                else if (disabled)
                  Icon(Icons.block_rounded, size: 17, color: c.warning),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoResult extends StatelessWidget {
  final String query;

  const _NoResult({required this.query});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 34, color: c.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text('Aucun opérateur pour « $query »',
                textAlign: TextAlign.center, style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text('Essayez le nom du réseau ou celui du pays.',
                textAlign: TextAlign.center, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}
