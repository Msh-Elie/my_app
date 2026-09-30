import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:switchmoney/ui_kit.dart';

/// Simule une frappe : `raw` est le texte obtenu, curseur en position
/// `cursor` (par defaut a la fin).
TextEditingValue apply(String raw, {int? cursor, String previous = ''}) {
  return const ThousandsInputFormatter().formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: cursor ?? raw.length),
    ),
  );
}

const nnbsp = '\u202F';

void main() {
  group('ThousandsInputFormatter', () {
    test('groupe les chiffres au fil de la frappe', () {
      expect(apply('2').text, '2');
      expect(apply('25').text, '25');
      expect(apply('250').text, '250');
      expect(apply('2500').text, '2${nnbsp}500');
      expect(apply('25000').text, '25${nnbsp}000');
      expect(apply('1234567').text, '1${nnbsp}234${nnbsp}567');
    });

    test('ignore tout ce qui n\'est pas un chiffre', () {
      // Le clavier numerique d'Android laisse passer virgules et espaces.
      expect(apply('25a00b0').text, '25${nnbsp}000');
      expect(apply('25 000').text, '25${nnbsp}000');
      expect(apply('25,000').text, '25${nnbsp}000');
    });

    test('rend un champ vide quand il ne reste aucun chiffre', () {
      expect(apply('').text, '');
      expect(apply('abc').text, '');
      expect(apply('').selection.baseOffset, 0);
    });

    test('laisse le curseur a la fin apres une frappe normale', () {
      final value = apply('25000');
      expect(value.text, '25${nnbsp}000');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('garde le curseur sur le meme chiffre apres insertion d\'un separateur',
        () {
      // L'utilisateur tape « 2500 » puis « 0 » : le texte passe de « 2 500 »
      // a « 25 000 ». Le curseur doit rester apres le 5e chiffre, pas reculer
      // d'un cran parce qu'une espace a ete inseree.
      final value = apply('25000', cursor: 5, previous: '2${nnbsp}500');
      expect(value.text, '25${nnbsp}000');
      final digitsBefore = value.text
          .substring(0, value.selection.baseOffset)
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      expect(digitsBefore, 5);
    });

    test('place correctement le curseur au milieu du nombre', () {
      // Curseur apres les deux premiers chiffres de « 1234567 ».
      final value = apply('1234567', cursor: 2);
      expect(value.text, '1${nnbsp}234${nnbsp}567');
      final digitsBefore = value.text
          .substring(0, value.selection.baseOffset)
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      expect(digitsBefore, 2);
    });

    test('le curseur reste dans les bornes du texte', () {
      for (final raw in ['1', '12', '123', '1234', '12345', '123456']) {
        for (var cursor = 0; cursor <= raw.length; cursor++) {
          final value = apply(raw, cursor: cursor);
          expect(value.selection.baseOffset, greaterThanOrEqualTo(0));
          expect(value.selection.baseOffset,
              lessThanOrEqualTo(value.text.length),
              reason: 'curseur hors du texte pour "$raw" en $cursor');
        }
      }
    });

    test('le texte formate se relit sans perte', () {
      // Garde-fou du calcul : le montant affiche doit toujours pouvoir
      // redevenir le nombre saisi.
      for (final raw in ['1', '500', '2500', '25000', '1234567']) {
        final shown = apply(raw).text;
        final back = shown.replaceAll(RegExp(r'[^0-9]'), '');
        expect(double.parse(back), double.parse(raw));
      }
    });
  });
}
