import 'package:flutter_test/flutter_test.dart';
import 'package:switchmoney/home_page.dart';

void main() {
  test('normalizeProvider leaves string unchanged', () {
    expect(normalizeProvider('MTN BJ'), 'MTN BJ');
    expect(normalizeProvider('MTN_BJ'), 'MTN_BJ');
    expect(normalizeProvider('some provider'), 'some provider');
  });

  group('Erreurs bloquantes (longueur / format national)', () {
    test('accepte les numéros béninois à 10 chiffres commençant par 01', () {
      expect(validateLocalNumberForProvider('MTN BJ', '0142123456'), isNull);
      expect(validateLocalNumberForProvider('MOOV BJ', '0195123456'), isNull);
    });

    test('rejette les numéros béninois trop courts ou sans 01', () {
      expect(validateLocalNumberForProvider('MTN BJ', '014912345'), isNotNull);
      expect(validateLocalNumberForProvider('MTN BJ', '9012345678'), isNotNull);
    });

    test('applique les longueurs par pays', () {
      expect(validateLocalNumberForProvider('MTN CI', '0512345678'), isNull);
      expect(validateLocalNumberForProvider('MTN CI', '051234567'), isNotNull);
      expect(validateLocalNumberForProvider('OM SN', '771234567'), isNull);
      expect(validateLocalNumberForProvider('OM SN', '7712345'), isNotNull);
      expect(validateLocalNumberForProvider('WAVE SN', '12345'), isNotNull);
    });

    test('un préfixe inhabituel ne bloque plus la saisie', () {
      // la vérité vient de PawaPay predict-provider au moment de l'envoi
      expect(validateLocalNumberForProvider('MTN CI', '0112345678'), isNull);
      expect(validateLocalNumberForProvider('OM SN', '701234567'), isNull);
      expect(validateLocalNumberForProvider('MTN GH', '0271234567'), isNull);
    });
  });

  group('Avertissements de préfixe (non bloquants)', () {
    test('silencieux quand le préfixe correspond', () {
      expect(prefixWarningForProvider('MTN BJ', '0142123456'), isNull);
      expect(prefixWarningForProvider('MTN CI', '0512345678'), isNull);
      expect(prefixWarningForProvider('OM CI', '0712345678'), isNull);
      expect(prefixWarningForProvider('MOOV CI', '0112345678'), isNull);
      expect(prefixWarningForProvider('MTN GH', '0241234567'), isNull);
      expect(prefixWarningForProvider('OM SN', '781234567'), isNull);
      expect(prefixWarningForProvider('VODAFONE GH', '0201234567'), isNull);
      expect(prefixWarningForProvider('OM ML', '76123456'), isNull);
    });

    test('averti quand le préfixe est inhabituel pour l\'opérateur', () {
      expect(prefixWarningForProvider('MTN BJ', '0145123456'), isNotNull);
      expect(prefixWarningForProvider('MTN CI', '0112345678'), isNotNull);
      expect(prefixWarningForProvider('OM SN', '701234567'), isNotNull);
      expect(prefixWarningForProvider('MTN GH', '0271234567'), isNotNull);
      expect(prefixWarningForProvider('MTN NG', '08051234567'), isNotNull);
    });

    test('silencieux pour les opérateurs sans règles de préfixe', () {
      expect(prefixWarningForProvider('WAVE SN', '771234567'), isNull);
      expect(prefixWarningForProvider('AIRTEL CD', '0991234567'), isNull);
    });
  });
}
