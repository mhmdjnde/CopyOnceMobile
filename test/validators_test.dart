import 'package:copy_once/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normal address', () {
      expect(Validators.email('user@example.com'), isNull);
    });

    test('accepts an address with subdomain and plus tag', () {
      expect(Validators.email('a.b+tag@mail.example.co.uk'), isNull);
    });

    test('trims surrounding whitespace before validating', () {
      expect(Validators.email('  user@example.com  '), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
    });

    test('rejects addresses without a domain dot', () {
      expect(Validators.email('user@example'), isNotNull);
    });

    test('rejects addresses without an @', () {
      expect(Validators.email('userexample.com'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('accepts a password at the minimum length', () {
      final password = 'a' * Validators.minPasswordLength;
      expect(Validators.password(password), isNull);
    });

    test('rejects a password one character short', () {
      final password = 'a' * (Validators.minPasswordLength - 1);
      expect(Validators.password(password), isNotNull);
    });

    test('rejects empty input', () {
      expect(Validators.password(''), isNotNull);
    });
  });

  group('Validators.requiredPassword', () {
    test(
      'accepts any non-empty value so short legacy passwords still submit',
      () {
        expect(Validators.requiredPassword('abc'), isNull);
      },
    );

    test('rejects empty input', () {
      expect(Validators.requiredPassword(''), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('accepts a matching value', () {
      expect(Validators.confirmPassword('secret123', 'secret123'), isNull);
    });

    test('rejects a mismatch', () {
      expect(Validators.confirmPassword('secret123', 'secret124'), isNotNull);
    });

    test('rejects empty input', () {
      expect(Validators.confirmPassword('', 'secret123'), isNotNull);
    });
  });

  group('Validators.displayName', () {
    test('accepts an empty name because it is optional', () {
      expect(Validators.displayName(''), isNull);
      expect(Validators.displayName(null), isNull);
    });

    test('accepts a normal name', () {
      expect(Validators.displayName('Sam'), isNull);
    });

    test('rejects a name over 50 characters', () {
      expect(Validators.displayName('x' * 51), isNotNull);
    });
  });
}
