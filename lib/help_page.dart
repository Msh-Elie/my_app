import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui_kit.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _topics = <_HelpTopic>[
    _HelpTopic(
      icon: Icons.send_rounded,
      title: 'Envoyer un transfert',
      body: 'Choisissez les deux opérateurs, saisissez les numéros puis le '
          'montant. Le récapitulatif affiche les frais et le montant net '
          'avant toute validation.',
    ),
    _HelpTopic(
      icon: Icons.verified_user_outlined,
      title: 'Vérification du bénéficiaire',
      body: 'Avant l\'envoi, le nom rattaché au numéro est recherché auprès '
          'de l\'opérateur. Si le nom ne s\'affiche pas, vérifiez le numéro '
          'avant de confirmer.',
    ),
    _HelpTopic(
      icon: Icons.schedule_rounded,
      title: 'Suivre le statut',
      body: 'Un transfert passe par « En cours » puis « Validé » ou « Échec ». '
          'L\'onglet Historique se met à jour automatiquement.',
    ),
    _HelpTopic(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Opérateurs disponibles',
      body: 'La liste vient directement des opérateurs actifs. Un opérateur '
          'peut être disponible à l\'envoi sans l\'être à la réception.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          const PageHeading(
            title: 'Centre d\'aide',
            subtitle: 'Les réponses aux questions les plus fréquentes.',
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final topic in _topics) ...[
            _HelpCard(topic: topic),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.sm),
          const SectionLabel('Nous contacter'),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.colors.brandSurface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: context.colors.brandText,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Support', style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'support@switchmoney.com',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpTopic {
  final IconData icon;
  final String title;
  final String body;

  const _HelpTopic({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _HelpCard extends StatelessWidget {
  final _HelpTopic topic;

  const _HelpCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(topic.icon, size: 19, color: c.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title, style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(topic.body, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
