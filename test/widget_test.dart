import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:switchmoney/api_client.dart';
import 'package:switchmoney/home_page.dart';
import 'package:switchmoney/main.dart';

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

    expect(find.text('SwitchMoney'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Numéro de téléphone (avec indicatif)'), findsOneWidget);
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
        home: HomePage(
          themeMode: ThemeMode.dark,
          onThemeChange: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('MTN BJ'), findsWidgets);
  });
}
