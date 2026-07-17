import 'package:flutter/material.dart';

import 'api_client.dart';
import 'help_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';

class MenuPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback? onLoggedOut;

  const MenuPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    this.onLoggedOut,
  });

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Déconnexion',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Se déconnecter',
                style: TextStyle(color: Colors.orange)),
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Menu', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFE6F0B),
              child: Icon(Icons.person, color: Colors.black),
            ),
            title: Text(
              user?.name ?? 'Utilisateur',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              user != null ? '+${user.phone}' : 'Non connecté',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.orange),
            title: const Text('Profil', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.orange),
            title: const Text('Paramètres',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsPage(
                      themeMode: themeMode, onThemeChanged: onThemeChanged),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.orange),
            title: const Text('Aide', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const HelpPage()));
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: const Text('Déconnexion',
                style: TextStyle(color: Colors.white)),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}
