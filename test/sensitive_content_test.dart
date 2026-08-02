import 'package:copy_once/utils/sensitive_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classify — definite secrets', () {
    test('recognises a PEM private key', () {
      expect(
        SensitiveContent.classify(
          '-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKC\n-----END RSA PRIVATE KEY-----',
        ),
        SensitiveKind.privateKey,
      );
    });

    test('recognises provider tokens by their published shapes', () {
      // Assembled at runtime rather than written out. A literal token shape in
      // a source file trips GitHub's secret scanner and blocks the push, even
      // though these are invented — and a fixture that looks like a live
      // credential is a bad habit regardless.
      const alpha = 'abcdefghijklmnopqrstuvwxyz';
      final tokens = [
        'sk-${alpha}123456',
        'sk_${'live'}_51H8xKjLkKdIwJkLmNoPqRs',
        'ghp_${alpha}0123456789',
        'AKIA${'IOSFODNN7EXAMPLE'}',
        'xox${'b'}-123456789012-abcdefghijklmno',
        'glpat-abcdefghij1234567890',
      ];

      for (final token in tokens) {
        expect(
          SensitiveContent.classify(token),
          SensitiveKind.apiToken,
          reason: token,
        );
      }
    });

    test('recognises a JWT', () {
      expect(
        SensitiveContent.classify(
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        SensitiveKind.jwt,
      );
    });
  });

  group('classify — card numbers', () {
    test('flags numbers that pass Luhn', () {
      // Well-known test numbers, not real cards.
      for (final card in [
        '4242424242424242',
        '4111 1111 1111 1111',
        '5555-5555-5555-4444',
      ]) {
        expect(
          SensitiveContent.classify(card),
          SensitiveKind.cardNumber,
          reason: card,
        );
      }
    });

    test('ignores long digit strings that fail Luhn', () {
      // Luhn is what stops every order reference becoming a card number.
      expect(
        SensitiveContent.classify('1234567812345678'),
        isNot(SensitiveKind.cardNumber),
      );
      expect(
        SensitiveContent.classify('Tracking 9400111899223197428490'),
        isNull,
      );
    });
  });

  group('classify — high entropy', () {
    test('flags a long random mixed string', () {
      expect(
        SensitiveContent.classify(r'Tr0ub4dor&3xKcd#9Zq!mVn2'),
        SensitiveKind.highEntropy,
      );
    });

    test('leaves ordinary content alone', () {
      const harmless = [
        'hello world',
        'Remember to call the dentist on Tuesday',
        'https://example.com/some/quite/long/path?with=query&more=params',
        'someone@example.com',
        'The quick brown fox jumps over the lazy dog',
        '42',
        'git commit -m "fix the thing"',
      ];

      for (final text in harmless) {
        expect(SensitiveContent.classify(text), isNull, reason: text);
      }
    });

    test('a repeated pattern is long but not random', () {
      expect(SensitiveContent.classify('Ab1Ab1Ab1Ab1Ab1Ab1Ab1Ab1'), isNull);
    });
  });

  group('mask', () {
    test('keeps enough to tell two secrets apart', () {
      final masked = SensitiveContent.mask('sk_live_51H8xKjLkKdIwJkLmNoPqRs');
      expect(masked.startsWith('sk_l'), isTrue);
      expect(masked.endsWith('PqRs'.substring(1)), isTrue);
      expect(masked.contains('••••'), isTrue);
    });

    test('never echoes the middle of the secret', () {
      const secret = 'sk_live_51H8xKjLkKdIwJkLmNoPqRs';
      final masked = SensitiveContent.mask(secret);
      expect(masked.contains('51H8xKjLkKdIwJkLmNo'), isFalse);
    });

    test('short values are fully hidden', () {
      expect(SensitiveContent.mask('abc123'), matches(RegExp(r'^•+$')));
    });
  });

  group('OneTimeCode', () {
    test('lifts the code out of a verification message', () {
      const messages = {
        'Your verification code is 123456': '123456',
        '847291 is your CopyOnce code': '847291',
        'Use OTP 4821 to sign in': '4821',
        'PIN: 9182': '9182',
      };

      messages.forEach((message, code) {
        expect(OneTimeCode.extract(message), code, reason: message);
      });
    });

    test('passes a bare code straight through', () {
      expect(OneTimeCode.extract('582910'), '582910');
    });

    test('does not invent codes from ordinary numbers', () {
      const notCodes = [
        'The meeting is at 1400 in room 2201',
        'Invoice 88213 is overdue',
        'I paid 4500 for it',
        'hello world',
      ];

      for (final text in notCodes) {
        expect(OneTimeCode.extract(text), isNull, reason: text);
      }
    });

    test('ignores anything long enough to be a document', () {
      expect(OneTimeCode.extract('code 1234 ${'x' * 500}'), isNull);
    });
  });
}
