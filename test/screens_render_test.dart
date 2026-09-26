import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:switchmoney/api_client.dart';
import 'package:switchmoney/help_page.dart';
import 'package:switchmoney/history_page.dart';
import 'package:switchmoney/home_page.dart';
import 'package:switchmoney/login_page.dart';
import 'package:switchmoney/menu_page.dart';
import 'package:switchmoney/profile_page.dart';
import 'package:switchmoney/register_page.dart';
import 'package:switchmoney/settings_page.dart';
import 'package:switchmoney/theme.dart';

/// Vérifie que chaque écran se construit sans erreur de rendu (débordement
/// compris) dans les deux thèmes. C'est le filet de sécurité du passage au
/// thème clair : une couleur oubliée ou une carte trop large ressort ici.
void main() {
  setUp(() {
    ApiClient.instance.resetForTests();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> expectRenders(
    WidgetTester tester,
    String name,
    Widget page,
  ) async {
    for (final theme in {'clair': AppTheme.light(), 'sombre': AppTheme.dark()}.entries) {
      // Gabarit d'un téléphone courant : c'est là que les débordements
      // apparaissent, pas sur la fenêtre 800x600 par défaut.
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: theme.value, home: page),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: '$name ne doit pas lever d\'erreur en thème ${theme.key}',
      );
    }
  }

  testWidgets('Connexion', (t) => expectRenders(t, 'LoginPage', const LoginPage()));

  testWidgets('Inscription',
      (t) => expectRenders(t, 'RegisterPage', const RegisterPage()));

  testWidgets('Accueil / transfert',
      (t) => expectRenders(t, 'HomePage', const HomePage()));

  testWidgets('Menu', (t) => expectRenders(t, 'MenuPage', const MenuPage()));

  testWidgets('Paramètres',
      (t) => expectRenders(t, 'SettingsPage', const SettingsPage()));

  testWidgets('Profil', (t) => expectRenders(t, 'ProfilePage', const ProfilePage()));

  testWidgets('Aide', (t) => expectRenders(t, 'HelpPage', const HelpPage()));

  testWidgets('Historique',
      (t) => expectRenders(t, 'HistoryPage', const HistoryPage()));

  testWidgets('Le tunnel de transfert traverse ses quatre étapes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomePage()),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Étape 0 : choix des opérateurs
    expect(find.text('D\'où vers où ?'), findsOneWidget);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    // Étape 1 : numéros
    expect(find.text('Les numéros'), findsOneWidget);
    expect(find.text('Étape 2 sur 4'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byType(TextField).first, '0151469075');
    await tester.enterText(
        find.byType(TextField).last, '0151469075');
    await tester.pump();

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    // Étape 2 : montant
    expect(find.text('Combien envoyer ?'), findsOneWidget);
    expect(find.text('Étape 3 sur 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
