import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'help_page.dart';
import 'server_settings_sheet.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'ui_kit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _notifKey = 'settings_notifications_v1';
  static const _bioKey = 'settings_biometric_v1';
  static const _langKey = 'settings_language_v1';

  bool notificationsEnabled = true;
  bool biometricEnabled = false;
  String language = 'Français';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      notificationsEnabled = prefs.getBool(_notifKey) ?? true;
      biometricEnabled = prefs.getBool(_bioKey) ?? false;
      language = prefs.getString(_langKey) ?? 'Français';
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _pickLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Langue', style: sheetContext.text.titleLarge),
              ),
            ),
            for (final option in const ['Français', 'Anglais'])
              ListTile(
                title: Text(option),
                trailing: option == language
                    ? Icon(Icons.check_rounded,
                        color: sheetContext.colors.brandText)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );

    if (selected == null) return;
    setState(() => language = selected);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, selected);
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          // ---- Apparence : thème clair par défaut, sombre au choix --------
          const SectionLabel('Apparence'),
          AnimatedBuilder(
            animation: themeController,
            builder: (context, _) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SettingIcon(icon: Icons.contrast_rounded),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Thème', style: context.text.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              'Choisissez l\'apparence de l\'application.',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ThemeSelector(
                    selected: themeController.mode,
                    onChanged: themeController.setMode,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Général'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingSwitch(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Alertes en temps réel sur vos transferts',
                  value: notificationsEnabled,
                  onChanged: (v) {
                    setState(() => notificationsEnabled = v);
                    _saveBool(_notifKey, v);
                  },
                ),
                const _SettingDivider(),
                _SettingSwitch(
                  icon: Icons.fingerprint_rounded,
                  title: 'Déverrouillage biométrique',
                  subtitle: 'Empreinte ou reconnaissance faciale',
                  value: biometricEnabled,
                  onChanged: (v) {
                    setState(() => biometricEnabled = v);
                    _saveBool(_bioKey, v);
                  },
                ),
                const _SettingDivider(),
                _SettingRow(
                  icon: Icons.translate_rounded,
                  title: 'Langue',
                  trailingLabel: language,
                  onTap: _pickLanguage,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Connexion'),
          AppCard(
            padding: EdgeInsets.zero,
            child: _SettingRow(
              icon: Icons.dns_outlined,
              title: 'Serveur backend',
              subtitle: ApiClient.instance.baseUrl,
              onTap: () async {
                await showServerSettingsSheet(context);
                if (mounted) setState(() {});
              },
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Assistance'),
          AppCard(
            padding: EdgeInsets.zero,
            child: _SettingRow(
              icon: Icons.help_outline_rounded,
              title: 'Centre d\'aide',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpPage()),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text('SwitchMoney • version 1.0.0',
                style: context.text.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur segmenté Clair / Sombre / Système.
class _ThemeSelector extends StatelessWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSelector({required this.selected, required this.onChanged});

  static const _options = <ThemeMode, IconData>{
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
    ThemeMode.system: Icons.phone_iphone_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: _options.entries.map((entry) {
          final isActive = entry.key == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: isActive ? c.cardShadow : null,
                  border: Border.all(
                    color: isActive ? c.border : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      entry.value,
                      size: 19,
                      color: isActive ? c.brandText : c.textMuted,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      ThemeController.labelFor(entry.key),
                      style: context.text.labelMedium?.copyWith(
                        color: isActive ? c.textPrimary : c.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  final IconData icon;

  const _SettingIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 19, color: c.textSecondary),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _SettingIcon(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: context.text.bodySmall),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final VoidCallback onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              _SettingIcon(icon: icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingLabel != null) ...[
                Text(trailingLabel!, style: context.text.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingDivider extends StatelessWidget {
  const _SettingDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: context.colors.border),
    );
  }
}
