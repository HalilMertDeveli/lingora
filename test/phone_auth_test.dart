import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/services/firebase/account_service.dart';

void main() {
  group('normalizePhoneTr', () {
    test('Turkish formats become E.164', () {
      for (final raw in [
        '0532 123 45 67',
        '532 123 45 67',
        '+90 532 123 45 67',
        '905321234567',
        '(0532) 123-45-67',
      ]) {
        expect(normalizePhoneTr(raw), '+905321234567', reason: raw);
      }
    });

    test('foreign numbers with a country code are kept', () {
      expect(normalizePhoneTr('+49 151 2345 6789'), '+4915123456789');
      expect(normalizePhoneTr('0049 151 2345 6789'), '+4915123456789');
    });

    test('invalid input is rejected', () {
      for (final raw in ['', '123', '0532 123', 'abc', '+0 532 123 45 67']) {
        expect(normalizePhoneTr(raw), isNull, reason: raw);
      }
    });
  });

  test('phone auth errors have Turkish messages', () {
    for (final code in [
      'invalid-phone-number',
      'invalid-verification-code',
      'session-expired',
      'quota-exceeded',
    ]) {
      expect(authErrorTr(code), isNot(contains(code)), reason: code);
    }
  });
}
