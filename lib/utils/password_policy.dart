/// The password rules CopyOnce enforces, in one place.
///
/// These mirror the Supabase project's password requirements so a password that
/// passes here is not rejected by the server. The server stays the authority:
/// a client pass is never authorization.
///
/// Composition rules are deliberately modest — length carries most of the real
/// strength, and forcing exotic symbols pushes people toward `Password1!` and a
/// sticky note. Symbols raise the strength score without being mandatory.
library;

/// A single requirement, so the UI can show which ones are still outstanding
/// instead of one vague error.
enum PasswordRule {
  length,
  lowercase,
  uppercase,
  digit,

  /// Not one of the passwords attackers try first.
  notCommon,

  /// Does not simply restate the email address.
  notEmailLike,
}

extension PasswordRuleLabel on PasswordRule {
  /// Wording for the checklist, phrased as the goal rather than the failure.
  String get label => switch (this) {
    PasswordRule.length => 'At least ${PasswordPolicy.minLength} characters',
    PasswordRule.lowercase => 'A lowercase letter',
    PasswordRule.uppercase => 'An uppercase letter',
    PasswordRule.digit => 'A number',
    PasswordRule.notCommon => 'Not a commonly used password',
    PasswordRule.notEmailLike => 'Different from your email address',
  };
}

/// How strong a password looks, for the meter. Not a security guarantee — a
/// password that satisfies every rule can still be guessable.
enum PasswordStrength { empty, weak, fair, good, strong }

extension PasswordStrengthLabel on PasswordStrength {
  String get label => switch (this) {
    PasswordStrength.empty => '',
    PasswordStrength.weak => 'Weak',
    PasswordStrength.fair => 'Fair',
    PasswordStrength.good => 'Good',
    PasswordStrength.strong => 'Strong',
  };

  /// Fraction of the meter to fill, 0–1.
  double get fraction => switch (this) {
    PasswordStrength.empty => 0,
    PasswordStrength.weak => 0.25,
    PasswordStrength.fair => 0.5,
    PasswordStrength.good => 0.75,
    PasswordStrength.strong => 1,
  };
}

/// The result of checking one password: which rules it meets and how strong it
/// looks.
class PasswordAssessment {
  const PasswordAssessment({required this.satisfied, required this.strength});

  final Set<PasswordRule> satisfied;
  final PasswordStrength strength;

  bool passes(PasswordRule rule) => satisfied.contains(rule);

  /// True when every rule is met and the password may be submitted.
  bool get isAcceptable => satisfied.length == PasswordRule.values.length;

  /// Rules still outstanding, in declaration order, for the checklist.
  Iterable<PasswordRule> get unmet =>
      PasswordRule.values.where((r) => !satisfied.contains(r));
}

abstract class PasswordPolicy {
  /// Long enough to matter, short enough that people will actually use it.
  /// Must match the project's Auth → Passwords minimum length.
  static const int minLength = 12;

  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9]');

  /// Passwords common enough that a credential-stuffing list would try them
  /// within the first handful of guesses. Compared case-insensitively, and any
  /// password *containing* one of the longer entries is treated as common too.
  ///
  /// A short local list, not a substitute for the server's leaked-password
  /// check — it exists to catch the obvious cases before a round trip.
  static const Set<String> _commonPasswords = {
    'password',
    'passw0rd',
    'password1',
    'password123',
    'qwerty',
    'qwerty123',
    'letmein',
    'welcome',
    'welcome1',
    'admin',
    'administrator',
    'iloveyou',
    'monkey',
    'dragon',
    'football',
    'baseball',
    'sunshine',
    'princess',
    'trustno1',
    'abc123',
    'abcd1234',
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    '111111',
    '000000',
    'copyonce',
    'clipboard',
  };

  /// Checks [password], optionally against the [email] it will protect.
  static PasswordAssessment assess(String password, {String? email}) {
    final satisfied = <PasswordRule>{};
    if (password.isEmpty) {
      return const PasswordAssessment(
        satisfied: {},
        strength: PasswordStrength.empty,
      );
    }

    if (password.length >= minLength) satisfied.add(PasswordRule.length);
    if (_lowercase.hasMatch(password)) satisfied.add(PasswordRule.lowercase);
    if (_uppercase.hasMatch(password)) satisfied.add(PasswordRule.uppercase);
    if (_digit.hasMatch(password)) satisfied.add(PasswordRule.digit);
    if (!_isCommon(password)) satisfied.add(PasswordRule.notCommon);
    if (!_resemblesEmail(password, email)) {
      satisfied.add(PasswordRule.notEmailLike);
    }

    return PasswordAssessment(
      satisfied: satisfied,
      strength: _strength(password, satisfied),
    );
  }

  /// Convenience for form validators: null when acceptable, otherwise the first
  /// unmet requirement phrased as an instruction.
  static String? validate(String? value, {String? email}) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';

    final assessment = assess(password, email: email);
    if (assessment.isAcceptable) return null;

    return switch (assessment.unmet.first) {
      PasswordRule.length => 'Use at least $minLength characters.',
      PasswordRule.lowercase => 'Add a lowercase letter.',
      PasswordRule.uppercase => 'Add an uppercase letter.',
      PasswordRule.digit => 'Add a number.',
      PasswordRule.notCommon => 'That password is too common to be safe.',
      PasswordRule.notEmailLike => 'Do not reuse your email address.',
    };
  }

  static bool _isCommon(String password) {
    final lower = password.toLowerCase();
    if (_commonPasswords.contains(lower)) return true;
    // Catch `myPassword123` and friends, but do not let a 3-letter entry like
    // `abc` condemn every password containing it.
    return _commonPasswords.any(
      (common) => common.length >= 6 && lower.contains(common),
    );
  }

  static bool _resemblesEmail(String password, String? email) {
    final address = email?.trim().toLowerCase() ?? '';
    if (address.isEmpty) return false;

    final lower = password.toLowerCase();
    if (lower == address) return true;

    final localPart = address.split('@').first;
    // Only meaningful for local parts long enough to be distinctive.
    return localPart.length >= 4 && lower.contains(localPart);
  }

  /// Blends length with variety: length dominates, variety breaks ties.
  static PasswordStrength _strength(
    String password,
    Set<PasswordRule> satisfied,
  ) {
    // A password failing a hard rule never reads as more than fair, so the
    // meter cannot say "Strong" next to a blocking error.
    final hasBlockingFailure =
        !satisfied.contains(PasswordRule.notCommon) ||
        !satisfied.contains(PasswordRule.notEmailLike);
    if (hasBlockingFailure) return PasswordStrength.weak;

    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= minLength) score++;
    if (password.length >= 16) score++;
    if (_symbol.hasMatch(password)) score++;
    if (satisfied.contains(PasswordRule.lowercase) &&
        satisfied.contains(PasswordRule.uppercase) &&
        satisfied.contains(PasswordRule.digit)) {
      score++;
    }

    return switch (score) {
      <= 1 => PasswordStrength.weak,
      2 => PasswordStrength.fair,
      3 => PasswordStrength.good,
      _ => PasswordStrength.strong,
    };
  }
}
