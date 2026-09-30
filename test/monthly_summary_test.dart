import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:switchmoney/history_storage.dart';
import 'package:switchmoney/monthly_summary.dart';
import 'package:switchmoney/recent_recipients.dart';

HistoryRecord record({
  required String amount,
  required String date,
  String status = 'valide',
}) =>
    HistoryRecord(
      id: 'tx-$date-$amount',
      from: 'MTN BJ',
      to: 'MOOV BJ',
      amount: amount,
      status: status,
      date: date,
    );

void main() {
  group('parseAmount', () {
    test('separe la valeur de la devise', () {
      expect(parseAmount('25000 XOF')?.value, 25000);
      expect(parseAmount('25000 XOF')?.currency, 'XOF');
      expect(parseAmount('3500 kes')?.currency, 'KES');
    });

    test('tolere un montant deja mis en forme', () {
      // L'historique local et celui du serveur ne formatent pas pareil.
      expect(parseAmount('120\u202F000\u00A0XOF')?.value, 120000);
      expect(parseAmount('1 234 567 XOF')?.value, 1234567);
    });

    test('rejette ce qui n\'est pas un montant', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('XOF'), isNull);
      expect(parseAmount('—'), isNull);
    });
  });

  group('computeMonthlyStats', () {
    final now = DateTime(2026, 9, 30);

    test('additionne les transferts valides du mois en cours', () {
      final stats = computeMonthlyStats([
        record(amount: '25000 XOF', date: '25/09/2026'),
        record(amount: '5000 XOF', date: '02/09/2026'),
      ], now: now);

      expect(stats.transferCount, 2);
      expect(stats.total, 30000);
      expect(stats.currency, 'XOF');
    });

    test('ecarte les mois precedents', () {
      final stats = computeMonthlyStats([
        record(amount: '25000 XOF', date: '25/09/2026'),
        record(amount: '99000 XOF', date: '31/08/2026'),
        record(amount: '99000 XOF', date: '25/09/2025'),
      ], now: now);

      expect(stats.transferCount, 1);
      expect(stats.total, 25000);
    });

    test('ecarte les echecs et les transferts en cours', () {
      // Un montant « envoye » qui compterait les echecs serait faux.
      final stats = computeMonthlyStats([
        record(amount: '25000 XOF', date: '25/09/2026'),
        record(amount: '10000 XOF', date: '26/09/2026', status: 'echec'),
        record(amount: '10000 XOF', date: '27/09/2026', status: 'en_cours'),
      ], now: now);

      expect(stats.transferCount, 1);
      expect(stats.total, 25000);
    });

    test('n\'additionne pas des devises differentes', () {
      final stats = computeMonthlyStats([
        record(amount: '25000 XOF', date: '25/09/2026'),
        record(amount: '3500 KES', date: '26/09/2026'),
      ], now: now);

      expect(stats.transferCount, 2);
      expect(stats.total, isNull, reason: 'XOF et KES ne s\'additionnent pas');
      expect(stats.currency, '');
    });

    test('est vide sans transfert exploitable', () {
      expect(computeMonthlyStats(const [], now: now).isEmpty, isTrue);
      expect(
        computeMonthlyStats([record(amount: 'n/a', date: 'hier')], now: now)
            .isEmpty,
        isTrue,
      );
    });
  });

  group('RecentRecipients', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('memorise puis relit un beneficiaire', () async {
      await RecentRecipients.remember(
        const RecentRecipient(
            phone: '0166000001', provider: 'MOOV BJ', name: 'AWA Koffi'),
      );

      final all = await RecentRecipients.load();
      expect(all, hasLength(1));
      expect(all.single.phone, '0166000001');
      expect(all.single.display, 'AWA Koffi');
    });

    test('remonte en tete sans dupliquer', () async {
      const a = RecentRecipient(phone: '0100000001', provider: 'MOOV BJ');
      const b = RecentRecipient(phone: '0100000002', provider: 'MOOV BJ');

      await RecentRecipients.remember(a);
      await RecentRecipients.remember(b);
      await RecentRecipients.remember(a);

      final all = await RecentRecipients.load();
      expect(all.map((r) => r.phone).toList(), ['0100000001', '0100000002']);
    });

    test('distingue le meme numero chez deux operateurs', () async {
      await RecentRecipients.remember(
          const RecentRecipient(phone: '0100000001', provider: 'MOOV BJ'));
      await RecentRecipients.remember(
          const RecentRecipient(phone: '0100000001', provider: 'MTN BJ'));

      expect(await RecentRecipients.load(), hasLength(2));
    });

    test('plafonne la liste', () async {
      for (var i = 0; i < RecentRecipients.maxEntries + 4; i++) {
        await RecentRecipients.remember(
          RecentRecipient(phone: '010000000$i', provider: 'MOOV BJ'),
        );
      }
      expect(await RecentRecipients.load(),
          hasLength(RecentRecipients.maxEntries));
    });

    test('filtre par operateur de destination', () async {
      await RecentRecipients.remember(
          const RecentRecipient(phone: '0100000001', provider: 'MOOV BJ'));
      await RecentRecipients.remember(
          const RecentRecipient(phone: '0100000002', provider: 'MTN BJ'));

      final all = await RecentRecipients.load();
      expect(RecentRecipients.forProvider(all, 'MTN BJ'), hasLength(1));
      expect(RecentRecipients.forProvider(all, 'WAVE CI'), isEmpty);
    });

    test('survit a un stockage illisible', () async {
      SharedPreferences.setMockInitialValues(
          {'recent_recipients_v1': 'pas du json'});
      expect(await RecentRecipients.load(), isEmpty);
    });
  });
}
