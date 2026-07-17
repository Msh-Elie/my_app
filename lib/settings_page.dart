import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'help_page.dart';
import 'server_settings_sheet.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsPage({super.key, required this.themeMode, required this.onThemeChanged});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        children: [
          const Text('Paramètres', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications, color: Colors.orange),
                  title: const Text('Notifications', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Activer les alertes en temps réel', style: TextStyle(color: Colors.white70)),
                  trailing: Switch(
                    value: notificationsEnabled,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) {
                      setState(() => notificationsEnabled = v);
                      _saveBool(_notifKey, v);
                    },
                  ),
                ),
                const Divider(color: Colors.white24, height: 0),
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.orange),
                  title: const Text('Sécurité', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Authentification biométrique', style: TextStyle(color: Colors.white70)),
                  trailing: Switch(
                    value: biometricEnabled,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) {
                      setState(() => biometricEnabled = v);
                      _saveBool(_bioKey, v);
                    },
                  ),
                ),
                const Divider(color: Colors.white24, height: 0),
                ListTile(
                  leading: const Icon(Icons.language, color: Colors.orange),
                  title: const Text('Langue', style: TextStyle(color: Colors.white)),
                  subtitle: Text(language, style: const TextStyle(color: Colors.white70)),
                  onTap: () async {
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return SimpleDialog(
                          backgroundColor: Colors.grey[900],
                          title: const Text('Choisir la langue', style: TextStyle(color: Colors.white)),
                          children: [
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, 'Français'),
                              child: const Text('Français', style: TextStyle(color: Colors.white)),
                            ),
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, 'Anglais'),
                              child: const Text('Anglais', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        );
                      },
                    );
                    if (selected != null) {
                      setState(() => language = selected);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(_langKey, selected);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Connexion au serveur', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Card(
            color: Colors.white10,
            child: ListTile(
              leading: const Icon(Icons.dns_outlined, color: Colors.orange),
              title: const Text('Serveur backend', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                ApiClient.instance.baseUrl,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () async {
                await showServerSettingsSheet(context);
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 12),
          const Text('Assistance', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Card(
            color: Colors.white10,
            child: ListTile(
              leading: const Icon(Icons.help, color: Colors.orange),
              title: const Text('Centre d\'aide', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const HelpPage()));
              },
            ),
          ),
        ],
      ),
    );
  }
}
