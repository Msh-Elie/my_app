import 'package:flutter/material.dart';

import 'api_client.dart';
import 'help_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'ui_kit.dart';

class MenuPage extends StatelessWidget {
  final VoidCallback? onLoggedOut;

  const MenuPage({super.key, this.onLoggedOut});

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Annuler',
              style: TextStyle(color: dialogContext.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Se déconnecter',
              style: TextStyle(color: dialogContext.colors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ApiClient.instance.logout();
    if (!context.mounted) return;
    // Revient à la racine ; l'AuthGate affichera l'écran de connexion.
    Navigator.of(context).popUntil((route) => route.isFirst);
    onLoggedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.user;
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          // Carte d'identité : l'utilisateur voit immédiatement sous quel
          // compte il agit.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
            child: Row(
              children: [
                _Avatar(name: user?.name),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Utilisateur',
                        style: context.text.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user != null ? '+${user.phone}' : 'Non connecté',
                        style: context.text.bodySmall?.copyWith(
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Préférences'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Profil',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  ),
                ),
                const _MenuDivider(),
                _MenuTile(
                  icon: Icons.tune_rounded,
                  label: 'Paramètres',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
                const _MenuDivider(),
                _MenuTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Aide',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: EdgeInsets.zero,
            child: _MenuTile(
              icon: Icons.logout_rounded,
              label: 'Déconnexion',
              tone: Tone.danger,
              showChevron: false,
              onTap: () => _confirmLogout(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille d'initiales, affichée à défaut de photo de profil.
class _Avatar extends StatelessWidget {
  final String? name;

  const _Avatar({this.name});

  String get _initials {
    final parts = (name ?? '').trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A3D), kBrand],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        _initials,
        style: context.text.titleMedium?.copyWith(
          color: context.colors.onBrand,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Tone tone;
  final bool showChevron;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = Tone.neutral,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = tone == Tone.danger ? c.danger : c.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tone == Tone.danger ? c.danger : c.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodyLarge?.copyWith(color: fg),
                ),
              ),
              if (showChevron)
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(height: 1, color: context.colors.border),
    );
  }
}
