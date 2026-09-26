import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:switchmoney/api_client.dart';
import 'package:switchmoney/home_page.dart';
import 'package:switchmoney/main.dart';
import 'package:switchmoney/theme.dart';
import 'package:switchmoney/theme_controller.dart';

void main() {
  setUp(() {
    // le singleton ApiClient garde son état entre deux tests
    ApiClient.instance.resetForTests();
  });

  testWidgets('Sans session, l\'app affiche l\'écran de connexion',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Bon retour'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Numéro de téléphone'), findsOneWidget);
  });

  testWidgets('Avec une session stockée, l\'app ouvre le flux de transfert',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token_v1': 'jeton-test',
      'auth_user_v1':
          '{"id":1,"phone":"22951469075","name":"Test User","email":null}',
    });

    await tester.pumpWidget(const MyApp());
    // pump borné (pas de pumpAndSettle : fetchMe() tourne en arrière-plan)
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Transfert'), findsWidgets);
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('MTN BJ'), findsWidgets);
  });

  testWidgets('Le flux de transfert rend les roues d\'opérateurs',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomePage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('MTN BJ'), findsWidgets);
  });

  group('ThemeController', () {
    test('démarre en clair quand rien n\'est enregistré', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.load();

      expect(controller.mode, ThemeMode.light);
    });

    test('restitue le mode sombre enregistré', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode_v1': 'dark',
      });
      final controller = ThemeController();
      await controller.load();

      expect(controller.mode, ThemeMode.dark);
    });

    test('enregistre le mode choisi', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.setMode(ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_mode_v1'), 'dark');
    });
  });
}
