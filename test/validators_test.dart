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
    test('delegates to the policy and accepts a conforming password', () {
      expect(Validators.password('Str0ngPassphrase'), isNull);
    });

    test('rejects a password that only meets the length rule', () {
      expect(
        Validators.password('a' * Validators.minPasswordLength),
        isNotNull,
      );
    });

    test('rejects empty input', () {
      expect(Validators.password(''), isNotNull);
    });

    test('rejects a password that restates the email', () {
      expect(
        Validators.password('Sunbeam1234', email: 'sunbeam1234@example.com'),
        isNotNull,
      );
    });
  });

  group('Validators.authenticatorCode', () {
    test('accepts six digits', () {
      expect(Validators.authenticatorCode('123456'), isNull);
    });

    test('rejects the wrong length', () {
      expect(Validators.authenticatorCode('12345'), isNotNull);
      expect(Validators.authenticatorCode('1234567'), isNotNull);
    });

    test('rejects non-digits', () {
      expect(Validators.authenticatorCode('12345a'), isNotNull);
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

  group('Validators.verificationCode', () {
    // Derived so the tests follow the configured length instead of pinning it.
    final code = '1' * Validators.verificationCodeLength;

    test('accepts a full-length code', () {
      expect(Validators.verificationCode(code), isNull);
    });

    test('accepts a code with surrounding whitespace', () {
      expect(Validators.verificationCode(' $code '), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.verificationCode(''), isNotNull);
      expect(Validators.verificationCode(null), isNotNull);
    });

    test('rejects the wrong length', () {
      expect(Validators.verificationCode(code.substring(1)), isNotNull);
      expect(Validators.verificationCode('${code}1'), isNotNull);
    });

    test('rejects non-digits', () {
      expect(Validators.verificationCode('${code.substring(1)}a'), isNotNull);
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
