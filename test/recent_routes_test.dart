import 'package:flutter_test/flutter_test.dart';

import 'package:switchmoney/history_storage.dart';
import 'package:switchmoney/recent_routes.dart';

HistoryRecord record(String from, String to) => HistoryRecord(
      id: '$from-$to-${DateTime.now().microsecondsSinceEpoch}',
      from: from,
      to: to,
      amount: '1000 XOF',
      status: 'valide',
      date: '04/10/2026',
    );

void main() {
  group('recentRoutes', () {
    test('conserve l\'ordre de l\'historique, du plus récent au plus ancien', () {
      final routes = recentRoutes([
        record('MTN BJ', 'MOOV BJ'),
        record('ORANGE CI', 'WAVE CI'),
      ]);

      expect(routes.map((r) => r.from).toList(), ['MTN BJ', 'ORANGE CI']);
    });

    test('écarte les doublons sans perdre le plus récent', () {
      final routes = recentRoutes([
        record('MTN BJ', 'MOOV BJ'),
        record('ORANGE CI', 'WAVE CI'),
        record('MTN BJ', 'MOOV BJ'),
      ]);

      expect(routes, hasLength(2));
      expect(routes.first, const TransferRoute(from: 'MTN BJ', to: 'MOOV BJ'));
    });

    test('distingue un trajet de son inverse', () {
      // MTN → MOOV et MOOV → MTN ne sont pas le même transfert.
      final routes = recentRoutes([
        record('MTN BJ', 'MOOV BJ'),
        record('MOOV BJ', 'MTN BJ'),
      ]);

      expect(routes, hasLength(2));
    });

    test('respecte la limite demandée', () {
      final routes = recentRoutes([
        record('A BJ', 'B BJ'),
        record('C BJ', 'D BJ'),
        record('E BJ', 'F BJ'),
        record('G BJ', 'H BJ'),
        record('I BJ', 'J BJ'),
      ], limit: 3);

      expect(routes, hasLength(3));
    });

    test('ignore les entrées incomplètes', () {
      final routes = recentRoutes([
        record('', 'MOOV BJ'),
        record('MTN BJ', ''),
        record('MTN BJ', 'MOOV BJ'),
      ]);

      expect(routes, hasLength(1));
    });

    test('renvoie une liste vide sans historique', () {
      expect(recentRoutes(const []), isEmpty);
    });
  });
}
