import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:switchmoney/api_client.dart';
import 'package:switchmoney/help_page.dart';
import 'package:switchmoney/history_page.dart';
import 'package:switchmoney/home_page.dart';
import 'package:switchmoney/login_page.dart';
import 'package:switchmoney/menu_page.dart';
import 'package:switchmoney/settings_page.dart';
import 'package:switchmoney/theme.dart';

/// Historique de démonstration : couvre les opérateurs avec logo, ceux sans,
/// et les trois statuts — c'est ce qui fait ressortir les défauts de rendu.
const _demoHistory = '''[
 {"id":"a1b2c3d4-5e6f-7890-abcd-ef1234567890","from":"MTN BJ","to":"MOOV BJ","amount":"25000 XOF","status":"valide","date":"25/09/2026"},
 {"id":"b2c3d4e5-6f70-8901-bcde-f12345678901","from":"MOOV BJ","to":"CELTIS BJ","amount":"5000 XOF","status":"en_cours","date":"25/09/2026"},
 {"id":"c3d4e5f6-7081-9012-cdef-123456789012","from":"ORANGE CI","to":"WAVE CI","amount":"120000 XOF","status":"echec","date":"24/09/2026"},
 {"id":"d4e5f607-8192-0123-def0-234567890123","from":"AIRTEL KE","to":"SAFARICOM KE","amount":"3500 KES","status":"valide","date":"24/09/2026"},
 {"id":"e5f60718-9203-1234-ef01-345678901234","from":"YAS TG","to":"MTN GH","amount":"8000 XOF","status":"valide","date":"20/09/2026"}
]''';

/// Rend chaque écran dans un fichier image, pour inspecter le design sans
/// appareil connecté.
///
///   flutter test test/golden_preview.dart --update-goldens
///
/// Le nom du fichier ne se termine pas par `_test` : il est donc ignoré par
/// `flutter test`, car il produit des images plutôt qu'il ne vérifie un
/// comportement — et les images dépendent des polices de la machine.
void main() {
  setUpAll(_loadRealFonts);

  setUp(() {
    ApiClient.instance.resetForTests();
    SharedPreferences.setMockInitialValues({
      'transfer_history_v1': _demoHistory,
    });
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    required ThemeData theme,
  }) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: theme, home: page));
    await _settleImages(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/$name.png'),
    );
  }

  for (final entry in {
    'clair': AppTheme.light(),
    'sombre': AppTheme.dark(),
  }.entries) {
    final suffix = entry.key;
    final theme = entry.value;

    testWidgets('connexion-$suffix',
        (t) => shoot(t, 'connexion-$suffix', const LoginPage(), theme: theme));
    testWidgets('accueil-$suffix',
        (t) => shoot(t, 'accueil-$suffix', const HomePage(), theme: theme));
    testWidgets('menu-$suffix',
        (t) => shoot(t, 'menu-$suffix', const MenuPage(), theme: theme));
    testWidgets('parametres-$suffix',
        (t) => shoot(t, 'parametres-$suffix', const SettingsPage(), theme: theme));
    testWidgets('aide-$suffix',
        (t) => shoot(t, 'aide-$suffix', const HelpPage(), theme: theme));
    testWidgets('historique-$suffix',
        (t) => shoot(t, 'historique-$suffix', const HistoryPage(), theme: theme));
  }

  testWidgets('transfert-montant-clair', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomePage()),
    );
    await _settleImages(tester);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0151469075');
    await tester.enterText(find.byType(TextField).last, '0166000001');
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '25000');
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/transfert-montant-clair.png'),
    );
  });

  testWidgets('transfert-confirmation-clair', (tester) async {
    await _pumpTransferToStep(tester, AppTheme.light(), step: 3);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/transfert-confirmation-clair.png'));
  });

  testWidgets('transfert-confirmation-sombre', (tester) async {
    await _pumpTransferToStep(tester, AppTheme.dark(), step: 3);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/transfert-confirmation-sombre.png'));
  });
}

/// Déroule le tunnel de transfert jusqu'à l'étape demandée.
Future<void> _pumpTransferToStep(
  WidgetTester tester,
  ThemeData theme, {
  required int step,
}) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: theme, home: const HomePage()));
  await _settleImages(tester);

  await tester.tap(find.text('Continuer'));
  await tester.pumpAndSettle();
  if (step == 1) return;

  await tester.enterText(find.byType(TextField).first, '0151469075');
  await tester.enterText(find.byType(TextField).last, '0166000001');
  await tester.pump();
  await tester.tap(find.text('Continuer'));
  await tester.pumpAndSettle();
  if (step == 2) return;

  await tester.enterText(find.byType(TextField).first, '25000');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Voir le récapitulatif'));
  await tester.pumpAndSettle();
}

/// Sans cela, les tests rendent le texte sous forme de rectangles : la
/// prévisualisation serait illisible.
Future<void> _loadRealFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontDir = r'C:\flutter\bin\cache\artifacts\material_fonts';
  final faces = {
    'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf'],
    'MaterialIcons': ['materialicons-regular.otf'],
  };

  for (final entry in faces.entries) {
    final loader = FontLoader(entry.key);
    var loadedAny = false;
    for (final file in entry.value) {
      final f = File('$fontDir${Platform.pathSeparator}$file');
      if (!f.existsSync()) continue;
      loader.addFont(
          f.readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
      loadedAny = true;
    }
    if (loadedAny) await loader.load();
  }
}

/// Les images d'assets se decodent de facon asynchrone : sans prechargement
/// explicite, `flutter test` rend des pastilles vides et la previsualisation
/// ne reflete pas ce que voit l'utilisateur.
Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  final context = tester.element(find.byType(MaterialApp).first);
  await tester.runAsync(() async {
    for (final asset in _logoAssets) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

const _logoAssets = [
  'assets/logos/mtn.png',
  'assets/logos/moov.png',
  'assets/logos/celtis.png',
  'assets/logos/orange.png',
  'assets/logos/wave.png',
  'assets/logos/vodafone.png',
  'assets/logos/safaricom.png',
];