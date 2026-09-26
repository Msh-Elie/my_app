import 'package:flutter_test/flutter_test.dart';

import 'package:switchmoney/history_page.dart';
import 'package:switchmoney/history_storage.dart';
import 'package:switchmoney/operators.dart';
import 'package:switchmoney/ui_kit.dart';

void main() {
  group('operatorBrand', () {
    test('retire le code pays de deux lettres', () {
      expect(operatorBrand('MTN BJ'), 'MTN');
      expect(operatorBrand('SAFARICOM KE'), 'SAFARICOM');
      expect(operatorBrand('MAROC TELECOM MA'), 'MAROC TELECOM');
    });

    test('tolère les libellés sans pays ou mal espacés', () {
      expect(operatorBrand('WAVE'), 'WAVE');
      expect(operatorBrand('  moov   bj '), 'MOOV');
      expect(operatorBrand(''), '');
    });
  });

  group('operatorLogoAsset', () {
    // Régression : une recherche par `contains` attribuait à SAFARICOM le logo
    // d'Orange, « SAFARICOM KE » contenant la sous-chaîne « OM ».
    test('SAFARICOM ne reçoit pas le logo d\'Orange', () {
      expect(operatorLogoAsset('SAFARICOM KE'), 'assets/logos/safaricom.png');
      expect(operatorLogoAsset('OM CI'), 'assets/logos/orange.png');
      expect(operatorLogoAsset('ORANGE CI'), 'assets/logos/orange.png');
    });

    test('associe les autres opérateurs connus', () {
      expect(operatorLogoAsset('MTN GH'), 'assets/logos/mtn.png');
      expect(operatorLogoAsset('MOOV BJ'), 'assets/logos/moov.png');
      expect(operatorLogoAsset('CELTIS BJ'), 'assets/logos/celtis.png');
      expect(operatorLogoAsset('AIRTEL KE'), 'assets/logos/airtel.svg');
    });

    test('renvoie null pour un opérateur sans logo (repli sur initiales)', () {
      expect(operatorLogoAsset('YAS TG'), isNull);
      expect(operatorInitials('YAS TG'), 'YAS');
      expect(operatorInitials('M-PESA CD'), 'M-P');
      expect(operatorInitials('MAROC TELECOM MA'), 'MT');
    });
  });

  group('formatThousands', () {
    test('groupe les chiffres par trois', () {
      expect(formatThousands('25000'), '25\u202F000');
      expect(formatThousands('120000'), '120\u202F000');
      expect(formatThousands('1234567'), '1\u202F234\u202F567');
    });

    test('laisse les petits nombres intacts', () {
      expect(formatThousands('500'), '500');
      expect(formatThousands('0'), '0');
    });
  });

  group('formatAmountLabel', () {
    test('met en forme un montant avec sa devise', () {
      expect(formatAmountLabel('25000 XOF'), '25\u202F000\u00A0XOF');
      expect(formatAmountLabel('3500 KES'), '3\u202F500\u00A0KES');
    });

    test('renvoie les valeurs inattendues telles quelles', () {
      expect(formatAmountLabel('—'), '—');
      expect(formatAmountLabel(''), '');
    });
  });

  group('dayLabel', () {
    final now = DateTime(2026, 9, 25);

    test('nomme les jours proches', () {
      expect(dayLabel(DateTime(2026, 9, 25), now: now), 'Aujourd\'hui');
      expect(dayLabel(DateTime(2026, 9, 24), now: now), 'Hier');
    });

    test('date en toutes lettres au-delà, avec l\'année si différente', () {
      expect(dayLabel(DateTime(2026, 9, 20), now: now), '20 septembre');
      expect(dayLabel(DateTime(2025, 12, 3), now: now), '3 décembre 2025');
    });
  });

  group('parseHistoryDate', () {
    test('lit le format jj/mm/aaaa', () {
      expect(parseHistoryDate('25/09/2026'), DateTime(2026, 9, 25));
    });

    test('rejette les formats invalides', () {
      expect(parseHistoryDate('hier'), isNull);
      expect(parseHistoryDate(''), isNull);
      expect(parseHistoryDate('99/99/2026'), isNull);
    });
  });

  group('groupByDay', () {
    HistoryRecord record(String id, String date) => HistoryRecord(
          id: id,
          from: 'MTN BJ',
          to: 'MOOV BJ',
          amount: '1000 XOF',
          status: 'valide',
          date: date,
        );

    final now = DateTime(2026, 9, 25);

    test('regroupe par jour, du plus récent au plus ancien', () {
      final groups = groupByDay([
        record('a', '20/09/2026'),
        record('b', '25/09/2026'),
        record('c', '24/09/2026'),
        record('d', '25/09/2026'),
      ], now: now);

      expect(groups.map((g) => g.label).toList(),
          ['Aujourd\'hui', 'Hier', '20 septembre']);
      expect(groups.first.items.map((e) => e.id).toList(), ['b', 'd']);
    });

    test('rassemble les dates illisibles à la fin plutôt que de les perdre', () {
      final groups = groupByDay([
        record('a', '25/09/2026'),
        record('b', 'date inconnue'),
      ], now: now);

      expect(groups.last.label, 'Autres');
      expect(groups.last.items.single.id, 'b');
      // Aucune opération ne doit disparaître du regroupement.
      expect(groups.fold<int>(0, (n, g) => n + g.items.length), 2);
    });

    test('renvoie une liste vide sans opération', () {
      expect(groupByDay(const [], now: now), isEmpty);
    });
  });
}
