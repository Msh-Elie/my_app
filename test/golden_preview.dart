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
import 'package:switchmoney/transfer_result.dart';
import 'package:switchmoney/ui_kit.dart';

/// Historique de démonstration : couvre les opérateurs avec logo, ceux sans,
/// et les trois statuts — c'est ce qui fait ressortir les défauts de rendu.
/// Historique de démonstration. Les dates sont calculées par rapport au jour
/// courant : figées, elles sortiraient du mois en cours et la carte
/// « Envoyé ce mois » disparaîtrait des aperçus au fil du temps.
String get _demoHistory {
  final now = DateTime.now();
  String day(int back) {
    final d = now.subtract(Duration(days: back));
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  return '''[
 {"id":"a1b2c3d4-5e6f-7890-abcd-ef1234567890","from":"MTN BJ","to":"MOOV BJ","amount":"25000 XOF","status":"valide","date":"${day(0)}"},
 {"id":"b2c3d4e5-6f70-8901-bcde-f12345678901","from":"MOOV BJ","to":"CELTIS BJ","amount":"5000 XOF","status":"en_cours","date":"${day(0)}"},
 {"id":"c3d4e5f6-7081-9012-cdef-123456789012","from":"ORANGE CI","to":"WAVE CI","amount":"120000 XOF","status":"echec","date":"${day(1)}"},
 {"id":"d4e5f607-8192-0123-def0-234567890123","from":"AIRTEL KE","to":"SAFARICOM KE","amount":"3500 KES","status":"en_cours","date":"${day(1)}"},
 {"id":"e5f60718-9203-1234-ef01-345678901234","from":"YAS TG","to":"MTN GH","amount":"8000 XOF","status":"valide","date":"${day(4)}"}
]''';
}

/// Beneficiaires recents de demonstration, pour l'etape des numeros.
const _demoRecipients = '''[
 {"phone":"0166000001","provider":"MOOV BJ","name":"AWA Koffi"},
 {"phone":"0195000042","provider":"MOOV BJ","name":null},
 {"phone":"0151469075","provider":"MTN BJ","name":"MENSAH Elie"}
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
      'recent_recipients_v1': _demoRecipients,
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

  testWidgets('accueil-premier-usage', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomePage()),
    );
    await _settleImages(tester);

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/accueil-premier-usage.png'));
  });

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

  testWidgets('transfert-numeros-clair', (tester) async {
    await _pumpTransferToStep(tester, AppTheme.light(), step: 1);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/transfert-numeros-clair.png'));
  });

  for (final entry in {
    'valide': const TransferResult(
      status: 'valide',
      txId: 'a1b2c3d4-5e6f-7890-abcd-ef1234567890',
      amount: '25000',
      currency: 'XOF',
      message: 'Le transfert a été confirmé par l\'opérateur.',
      date: '06/10/2026',
      from: 'MTN BJ',
      to: 'MOOV BJ',
      receiverName: 'AWA Koffi',
      receiverPhone: '+229 01 95 00 00 42',
    ),
    'en-cours': const TransferResult(
      status: 'en_cours',
      txId: 'b2c3d4e5-6f70-8901-bcde-f12345678901',
      amount: '5000',
      currency: 'XOF',
      message: 'Dépôt initié — confirmation de l\'opérateur en cours…',
      date: '06/10/2026',
      from: 'MOOV BJ',
      to: 'MTN BJ',
      receiverPhone: '+229 01 66 00 00 75',
    ),
    'echec': const TransferResult(
      status: 'echec',
      txId: 'c3d4e5f6-7081-9012-cdef-123456789012',
      amount: '120000',
      currency: 'XOF',
      message: 'Le transfert a échoué. Aucun montant ne sera prélevé.',
      date: '05/10/2026',
      from: 'ORANGE CI',
      to: 'WAVE CI',
      receiverPhone: '+225 07 01 20 00 00',
    ),
  }.entries) {
    testWidgets('resultat-${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SafeArea(
          child: TransferResultView(
            result: entry.value,
            onViewHistory: () {},
          ))),
      ));
      await _settleImages(tester);
      // Laisse la coche finir de se tracer.
      await tester.pump(const Duration(milliseconds: 1100));

      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('previews/resultat-${entry.key}.png'));
    });
  }

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
  testWidgets('selecteur-operateurs-clair', (tester) async {
    await _pumpOperatorPicker(tester, AppTheme.light());
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/selecteur-operateurs-clair.png'));
  });

  testWidgets('selecteur-operateurs-sombre', (tester) async {
    await _pumpOperatorPicker(tester, AppTheme.dark());
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('previews/selecteur-operateurs-sombre.png'));
  });
  for (final entry in {
    'clair': AppTheme.light(),
    'sombre': AppTheme.dark(),
  }.entries) {
    testWidgets('composants-${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1080, 1800);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: entry.value,
        home: const _ComponentSheet(),
      ));
      // Laisse la coche finir de se tracer avant la capture.
      await tester.pump(const Duration(milliseconds: 1200));

      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('previews/composants-${entry.key}.png'));
    });
  }
}

/// Planche des composants du systeme de design.
class _ComponentSheet extends StatelessWidget {
  const _ComponentSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 46),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  AnimatedCheck(
                      size: 76, color: c.success, background: c.successSurface),
                  const SizedBox(width: AppSpacing.lg),
                  const Expanded(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        StatusPill(
                            label: 'Valide',
                            tone: Tone.success,
                            icon: Icons.check_rounded),
                        StatusPill(
                            label: 'En cours',
                            tone: Tone.warning,
                            icon: Icons.schedule_rounded),
                        StatusPill(
                            label: 'Echec',
                            tone: Tone.danger,
                            icon: Icons.close_rounded),
                        StatusPill(label: 'Neutre'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const InfoBanner(message: 'Encart d\'information de reference.'),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  children: [
                    DetailRow(label: 'Montant envoye', value: '25000 XOF'),
                    DetailRow(label: 'Frais', value: '500 XOF'),
                    Divider(height: AppSpacing.xl, color: c.border),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Le beneficiaire recoit',
                              style: context.text.titleSmall),
                        ),
                        AnimatedAmount(
                          value: 24500,
                          currency: 'XOF',
                          style: context.text.titleLarge
                              ?.copyWith(color: c.brandText),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const StepProgress(currentStep: 2, totalSteps: 4, labels: [
                'Operateurs',
                'Numeros',
                'Montant',
                'Verification',
              ]),
              const SizedBox(height: AppSpacing.xl),
              const PrimaryButton(label: 'Bouton principal'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouvre la feuille de choix d'operateur depuis la premiere etape.
Future<void> _pumpOperatorPicker(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: theme, home: const HomePage()));
  await _settleImages(tester);

  await tester.tap(find.text('DEPUIS'));
  await tester.pumpAndSettle();
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