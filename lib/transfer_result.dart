import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'operators.dart';
import 'theme.dart';
import 'ui_kit.dart';

/// Issue d'un transfert, telle qu'affichée à la dernière étape.
class TransferResult {
  /// `valide`, `echec`, ou `en_cours`.
  final String status;
  final String? txId;

  /// Montant en chiffres seuls (« 25000 ») et sa devise.
  final String? amount;
  final String? currency;

  final String? message;
  final String? date;
  final String? from;
  final String? to;

  /// Nom du bénéficiaire quand l'opérateur a pu le résoudre.
  final String? receiverName;

  /// Numéro du bénéficiaire, mis en forme pour l'affichage.
  final String? receiverPhone;

  /// Lien à ouvrir quand l'opérateur exige une validation sur une page
  /// externe (cas des rails hors PawaPay).
  final String? checkoutUrl;

  const TransferResult({
    required this.status,
    this.txId,
    this.amount,
    this.currency,
    this.message,
    this.date,
    this.from,
    this.to,
    this.receiverName,
    this.receiverPhone,
    this.checkoutUrl,
  });

  bool get isSuccess => status == 'valide';
  bool get isFailure => status == 'echec';

  Tone get tone => isSuccess
      ? Tone.success
      : isFailure
          ? Tone.danger
          : Tone.warning;

  String get label => isSuccess
      ? 'Transfert validé'
      : isFailure
          ? 'Transfert échoué'
          : 'Transfert en cours';

  /// Montant mis en forme, ou `null` s'il est inconnu.
  String? get formattedAmount {
    final raw = '${amount ?? ''} ${currency ?? ''}'.trim();
    if (raw.isEmpty || amount == null) return null;
    return formatAmountLabel(raw);
  }
}

/// Dernière étape du tunnel : ce qui vient de se passer.
///
/// L'écran présentait auparavant le montant comme une ligne parmi quatre, au
/// milieu de la date et de la référence. Or après un envoi d'argent, c'est le
/// montant que l'on cherche des yeux : il devient ici le sujet, la coche dit
/// l'issue, et les éléments de traçabilité passent derrière.
class TransferResultView extends StatelessWidget {
  final TransferResult result;

  /// Ouvre l'historique. Absent, le lien n'est pas proposé.
  final VoidCallback? onViewHistory;

  const TransferResultView({
    super.key,
    required this.result,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final amount = result.formattedAmount;

    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusMark(result: result),
          const SizedBox(height: AppSpacing.md),

          Text(
            result.label,
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(
              color: result.tone.foreground(context),
            ),
          ),

          if (amount != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              amount,
              textAlign: TextAlign.center,
              style: context.text.displaySmall?.copyWith(
                fontSize: 38,
                fontFeatures: kTabularFigures,
              ),
            ),
          ],

          if (result.from != null && result.to != null) ...[
            const SizedBox(height: AppSpacing.md),
            _RouteLine(from: result.from!, to: result.to!),
          ],

          const SizedBox(height: AppSpacing.md),
          Text(
            result.message ?? 'Votre opération a été enregistrée.',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium,
          ),

          const SizedBox(height: AppSpacing.xl),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BÉNÉFICIAIRE', style: context.text.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                if (result.receiverName != null)
                  Text(result.receiverName!, style: context.text.titleSmall),
                if (result.receiverPhone != null)
                  Text(
                    result.receiverPhone!,
                    style: context.text.bodyMedium?.copyWith(
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                if (result.receiverName == null && result.receiverPhone == null)
                  Text('—', style: context.text.bodyMedium),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Divider(height: 1, color: context.colors.border),
                ),
                DetailRow(label: 'Date', value: result.date ?? '—'),
              ],
            ),
          ),

          if (result.txId != null && result.txId!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _ReferenceCard(reference: result.txId!),
          ],

          if (result.checkoutUrl != null) ...[
            const SizedBox(height: AppSpacing.md),
            _CheckoutCard(url: result.checkoutUrl!),
          ],

          if (onViewHistory != null) ...[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton.icon(
                onPressed: onViewHistory,
                icon: const Icon(Icons.receipt_long_rounded, size: 17),
                label: const Text('Voir dans l\'historique'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastille d'état : la coche se trace pour un succès, les autres issues
/// restent immobiles — on ne met pas en scène une mauvaise nouvelle.
class _StatusMark extends StatelessWidget {
  final TransferResult result;

  const _StatusMark({required this.result});

  @override
  Widget build(BuildContext context) {
    final tone = result.tone;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutBack,
        builder: (context, value, child) =>
            Transform.scale(scale: 0.7 + (value * 0.3), child: child),
        child: result.isSuccess
            ? AnimatedCheck(
                size: 72,
                color: tone.foreground(context),
                background: tone.background(context),
              )
            : Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: tone.background(context),
                  shape: BoxShape.circle,
                ),
                child: result.isFailure
                    ? Icon(Icons.close_rounded,
                        size: 36, color: tone.foreground(context))
                    : Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: tone.foreground(context),
                          ),
                        ),
                      ),
              ),
      ),
    );
  }
}

/// Trajet emprunté, logos à l'appui.
///
/// La flèche est une icône et non le caractère « → » : toutes les polices ne
/// le dessinent pas, et un glyphe manquant au milieu d'un reçu fait mauvais
/// effet.
class _RouteLine extends StatelessWidget {
  final String from;
  final String to;

  const _RouteLine({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OperatorPair(from: from, to: to, size: 28),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: operatorBrand(from)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 13, color: c.textMuted),
                  ),
                ),
                TextSpan(text: operatorBrand(to)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall,
          ),
        ),
      ],
    );
  }
}

/// Référence de l'opération, copiable.
///
/// C'est ce qu'on transmet au support en cas de litige : elle mérite d'être
/// lisible et d'être reprise d'un geste, pas recopiée à la main.
class _ReferenceCard extends StatelessWidget {
  final String reference;

  const _ReferenceCard({required this.reference});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RÉFÉRENCE', style: context.text.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  reference,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copier la référence',
            icon: Icon(Icons.copy_rounded, size: 18, color: c.textMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: reference));
              showAppSnack(context, 'Référence copiée', tone: Tone.success);
            },
          ),
        ],
      ),
    );
  }
}

/// Lien de validation externe, quand l'opérateur en impose un.
class _CheckoutCard extends StatelessWidget {
  final String url;

  const _CheckoutCard({required this.url});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 18, color: c.brandText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child:
                    Text('Validation à finaliser', style: context.text.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ouvrez ce lien pour confirmer le paiement auprès de votre '
            'opérateur, puis revenez dans l\'application.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            url,
            style: context.text.bodySmall?.copyWith(color: c.brandText),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              showAppSnack(context, 'Lien copié', tone: Tone.success);
            },
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('Copier le lien'),
          ),
        ],
      ),
    );
  }
}
