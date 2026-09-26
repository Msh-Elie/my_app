import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conserve le thème choisi par l'utilisateur et le restitue au démarrage.
///
/// Le thème **clair est le défaut** (comme la majorité des applications
/// bancaires) ; l'utilisateur peut basculer en sombre, ou suivre le réglage
/// du système, depuis Paramètres → Apparence.
class ThemeController extends ChangeNotifier {
  /// Instance unique, sur le même modèle que `ApiClient.instance` déjà utilisé
  /// dans l'application : les écrans y accèdent sans avoir à se transmettre le
  /// thème de parent en enfant.
  static final ThemeController instance = ThemeController();

  static const _prefsKey = 'settings_theme_mode_v1';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  /// Recharge la préférence enregistrée. Si rien n'est stocké (première
  /// ouverture) ou si la valeur est illisible, on reste en clair.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      final restored = _decode(stored);
      if (restored != _mode) {
        _mode = restored;
        notifyListeners();
      }
    } catch (_) {
      // Stockage indisponible : le thème clair par défaut reste valable.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(mode));
    } catch (_) {
      // Échec d'écriture : le choix reste actif pour la session en cours.
    }
  }

  static ThemeMode _decode(String? value) => switch (value) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };

  /// Libellé affiché dans les écrans de réglage.
  static String labelFor(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Clair',
        ThemeMode.dark => 'Sombre',
        ThemeMode.system => 'Système',
      };
}
