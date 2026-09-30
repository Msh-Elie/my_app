import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Vérifie la cohérence des ressources Android de l'écran de lancement.
///
/// Ces fichiers ne sont couverts par aucun test de widget : ils sont inflatés
/// par Android *avant* que Flutter ne démarre. Une erreur ici ne se voit donc
/// qu'au lancement sur un appareil, sous la forme d'un plantage immédiat —
/// c'est exactement ce qui s'est produit lorsque l'icône de lancement est
/// devenue adaptative :
///
///   XmlPullParserException: `<bitmap>` requires a valid `src` attribute
///
/// `@mipmap/ic_launcher` désigne alors `mipmap-anydpi-v26/ic_launcher.xml`,
/// un `<adaptive-icon>` que la balise `<bitmap>` ne sait pas charger.
void main() {
  final res = Directory('android/app/src/main/res');

  final launchBackgrounds = [
    File('${res.path}/drawable/launch_background.xml'),
    File('${res.path}/drawable-v21/launch_background.xml'),
  ];

  // `android:src="..."` hors des lignes de commentaire.
  final srcPattern = RegExp(r'android:src\s*=\s*"([^"]+)"');

  for (final file in launchBackgrounds) {
    group(file.path.split('/').last +
        (file.path.contains('-v21') ? ' (v21)' : ''), () {
      test('le fichier existe', () {
        expect(file.existsSync(), isTrue, reason: '${file.path} est introuvable');
      });

      test('aucun <bitmap> ne pointe vers une icône adaptative', () {
        final content = file.readAsStringSync();
        final sources = srcPattern
            .allMatches(content)
            .map((m) => m.group(1)!)
            .toList();

        expect(sources, isNotEmpty,
            reason: 'le splash devrait afficher un logo');

        for (final source in sources) {
          expect(
            source.startsWith('@mipmap/'),
            isFalse,
            reason: '$source est une icône de lancement : sur API 26+ elle est '
                'un XML <adaptive-icon>, que <bitmap> ne peut pas charger. '
                'Utilisez une image matricielle de @drawable/.',
          );
        }
      });

      test('chaque image référencée existe dans au moins une densité', () {
        final content = file.readAsStringSync();
        for (final match in srcPattern.allMatches(content)) {
          final source = match.group(1)!;
          if (!source.startsWith('@drawable/')) continue;
          final name = source.substring('@drawable/'.length);

          final buckets = res
              .listSync()
              .whereType<Directory>()
              .where((d) => d.path.split(RegExp(r'[/\\]')).last
                  .startsWith('drawable'));

          final found = buckets.any((d) =>
              File('${d.path}/$name.png').existsSync() ||
              File('${d.path}/$name.xml').existsSync() ||
              File('${d.path}/$name.webp').existsSync());

          expect(found, isTrue,
              reason: '$source est référencé mais aucun fichier '
                  '$name.(png|xml|webp) n\'existe sous res/drawable*');
        }
      });
    });
  }

  test('l\'icône adaptative garde un fond et un avant-plan valides', () {
    final adaptive = File('${res.path}/mipmap-anydpi-v26/ic_launcher.xml');
    expect(adaptive.existsSync(), isTrue);

    final content = adaptive.readAsStringSync();
    expect(content, contains('<adaptive-icon'));
    expect(content, contains('android:drawable="@color/ic_launcher_background"'));
    expect(content, contains('android:drawable="@drawable/ic_launcher_foreground"'));

    // Le fond de l'icône est une couleur : elle doit être déclarée.
    final colors = File('${res.path}/values/colors.xml').readAsStringSync();
    expect(colors, contains('name="ic_launcher_background"'));
    expect(colors, contains('name="splash_background"'));
  });
}
