import 'package:flutter_test/flutter_test.dart';
import 'package:switchmoney/home_page.dart';

void main() {
  group('normalize', () {
    test('conserve number without extra zero', () {
      expect(normalize('22951469075'), '22951469075');
    });

    test('strips national zero after code', () {
      // only the leading zero after the country code is removed
      expect(normalize('2290151469075'), '229151469075');
      expect(normalize('237012345678'), '23712345678');
    });

    test('removes zero when present, otherwise leaves intact', () {
      expect(normalize('123'), '123');
      expect(normalize('229001234'), '22901234');
    });
  });

  group('tryNormalizeCorrection', () {
    test('identical numbers yields same normalized', () {
      final result = tryNormalizeCorrection('2290151469075', '2290151469075');
      expect(result, normalize('2290151469075'));
    });

    test('predict has extra zero → correction', () {
      final result = tryNormalizeCorrection('22951469075', '229051469075');
      expect(result, '22951469075'); // both normalize to the same final MSISDN
    });

    test('incompatible numbers returns null', () {
      final result = tryNormalizeCorrection('22951469075', '23712345678');
      expect(result, isNull);
    });
  });
}
