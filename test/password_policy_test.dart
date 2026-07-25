import 'package:copy_once/utils/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rules', () {
    test('a long mixed password satisfies every rule', () {
      final assessment = PasswordPolicy.assess('Str0ngPassphrase');

      expect(assessment.isAcceptable, isTrue);
      expect(assessment.unmet, isEmpty);
    });

    test('length alone is not enough', () {
      final assessment = PasswordPolicy.assess('aaaaaaaaaaaaaaaa');

      expect(assessment.isAcceptable, isFalse);
      expect(assessment.passes(PasswordRule.length), isTrue);
      expect(assessment.passes(PasswordRule.uppercase), isFalse);
      expect(assessment.passes(PasswordRule.digit), isFalse);
    });

    test('a short password fails the length rule', () {
      final short =
          'Ab1'
          'defg'; // 7 characters
      expect(PasswordPolicy.assess(short).passes(PasswordRule.length), isFalse);
    });

    test('an empty password satisfies nothing and reads as empty', () {
      final assessment = PasswordPolicy.assess('');

      expect(assessment.satisfied, isEmpty);
      expect(assessment.strength, PasswordStrength.empty);
    });
  });

  group('common passwords', () {
    test('rejects an exact match regardless of case', () {
      expect(
        PasswordPolicy.assess('PASSWORD123').passes(PasswordRule.notCommon),
        isFalse,
      );
    });

    test('rejects a long common password used as a substring', () {
      expect(
        PasswordPolicy.assess('Xyzpassword12A').passes(PasswordRule.notCommon),
        isFalse,
      );
    });

    test('does not reject over a short substring like abc', () {
      expect(
        PasswordPolicy.assess('Abcdefgh1jklmn').passes(PasswordRule.notCommon),
        isTrue,
      );
    });
  });

  group('email similarity', () {
    test('rejects a password containing the email local part', () {
      final assessment = PasswordPolicy.assess(
        'Jndeishere2026',
        email: 'jndeishere@gmail.com',
      );

      expect(assessment.passes(PasswordRule.notEmailLike), isFalse);
    });

    test('accepts an unrelated password for the same email', () {
      final assessment = PasswordPolicy.assess(
        'Str0ngPassphrase',
        email: 'jndeishere@gmail.com',
      );

      expect(assessment.passes(PasswordRule.notEmailLike), isTrue);
    });

    test('ignores a very short local part rather than over-matching', () {
      // 'ab' appears in the password but is too short to be distinctive.
      final assessment = PasswordPolicy.assess(
        'Absolute1Value',
        email: 'ab@example.com',
      );

      expect(assessment.passes(PasswordRule.notEmailLike), isTrue);
    });

    test('passes when no email is supplied', () {
      expect(
        PasswordPolicy.assess(
          'Str0ngPassphrase',
        ).passes(PasswordRule.notEmailLike),
        isTrue,
      );
    });
  });

  group('strength', () {
    test('a blocking failure never reads better than weak', () {
      // Long and varied, but a known common password.
      final assessment = PasswordPolicy.assess('Password123456');

      expect(assessment.strength, PasswordStrength.weak);
    });

    test('grows with length', () {
      final short = PasswordPolicy.assess('Ab1defgh').strength;
      final medium = PasswordPolicy.assess('Ab1defghijkl').strength;
      final long = PasswordPolicy.assess('Ab1defghijklmnop').strength;

      expect(short.fraction, lessThan(medium.fraction));
      expect(medium.fraction, lessThanOrEqualTo(long.fraction));
    });

    test('a symbol raises the score without being required', () {
      final withoutSymbol = PasswordPolicy.assess('Ab1defghijkl');
      final withSymbol = PasswordPolicy.assess('Ab1defghijk!');

      expect(withoutSymbol.isAcceptable, isTrue);
      expect(
        withSymbol.strength.fraction,
        greaterThan(withoutSymbol.strength.fraction),
      );
    });
  });

  group('validate', () {
    test('returns null for an acceptable password', () {
      expect(PasswordPolicy.validate('Str0ngPassphrase'), isNull);
    });

    test('names the length rule first when several are unmet', () {
      expect(
        PasswordPolicy.validate('ab'),
        'Use at least ${PasswordPolicy.minLength} characters.',
      );
    });

    test('asks for an uppercase letter when only that is missing', () {
      expect(
        PasswordPolicy.validate('str0ngpassphrase'),
        'Add an uppercase letter.',
      );
    });

    test('reports empty input plainly', () {
      expect(PasswordPolicy.validate(''), 'Enter a password.');
      expect(PasswordPolicy.validate(null), 'Enter a password.');
    });
  });
}
