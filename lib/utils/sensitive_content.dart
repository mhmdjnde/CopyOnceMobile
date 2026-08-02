/// Recognises copied text that looks like a secret.
///
/// People copy passwords, tokens, and card numbers constantly — that is what a
/// password manager is for. CopyOnce carries whatever is on the clipboard, so
/// without this a secret is shown in full in a list that may be open on a
/// screen someone else can see.
///
/// The rules are deliberately conservative. A false positive costs a tap to
/// reveal; a false negative shows a live API key to the room. Where the two
/// trade off, this leans towards masking.
///
/// Mirrored in web/src/lib/sensitive-content.ts — the two are one ruleset
/// written twice, and a parity test keeps them honest.
library;

/// Why a value was treated as sensitive, so the UI can say something specific.
enum SensitiveKind {
  /// A PEM block. Never anything but a secret.
  privateKey,

  /// A recognised provider token — Stripe, GitHub, AWS, Google, Slack.
  apiToken,

  /// A JSON Web Token. Often a live session.
  jwt,

  /// Digits that pass the Luhn check at a card's length.
  cardNumber,

  /// Long, random-looking, no spaces. The catch-all for passwords and keys
  /// that carry no recognisable prefix.
  highEntropy,
}

extension SensitiveKindLabel on SensitiveKind {
  /// Named for what the user would call it, not for how it was detected.
  String get label => switch (this) {
    SensitiveKind.privateKey => 'Private key',
    SensitiveKind.apiToken => 'API key',
    SensitiveKind.jwt => 'Access token',
    SensitiveKind.cardNumber => 'Card number',
    SensitiveKind.highEntropy => 'Possible password',
  };
}

abstract class SensitiveContent {
  /// Token shapes published by the providers themselves, so a match is a fact
  /// rather than a guess.
  static final List<RegExp> _tokenPatterns = [
    RegExp(r'\bsk-[A-Za-z0-9]{20,}'), // OpenAI
    RegExp(r'\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}'), // Stripe
    RegExp(r'\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}'), // GitHub
    RegExp(r'\bgithub_pat_[A-Za-z0-9_]{50,}'), // GitHub fine-grained
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'), // AWS access key id
    RegExp(r'\bASIA[0-9A-Z]{16}\b'), // AWS temporary key id
    RegExp(r'\bAIza[0-9A-Za-z_\-]{35}\b'), // Google API key
    RegExp(r'\bya29\.[0-9A-Za-z_\-]{20,}'), // Google OAuth
    RegExp(r'\bxox[baprs]-[0-9A-Za-z\-]{10,}'), // Slack
    RegExp(r'\bglpat-[0-9A-Za-z_\-]{20,}'), // GitLab
    RegExp(r'\bsbp_[0-9a-f]{40,}'), // Supabase
    RegExp(r'\bnpm_[A-Za-z0-9]{36}\b'), // npm
  ];

  static final RegExp _privateKey = RegExp(
    r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
  );

  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}',
  );

  /// 13–19 digits, optionally grouped by spaces or hyphens.
  static final RegExp _cardCandidate = RegExp(r'\b(?:\d[ -]?){12,18}\d\b');

  /// What kind of secret this looks like, or null when it looks like ordinary
  /// content.
  static SensitiveKind? classify(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    if (_privateKey.hasMatch(trimmed)) return SensitiveKind.privateKey;
    if (_jwt.hasMatch(trimmed)) return SensitiveKind.jwt;

    for (final pattern in _tokenPatterns) {
      if (pattern.hasMatch(trimmed)) return SensitiveKind.apiToken;
    }

    if (_looksLikeCard(trimmed)) return SensitiveKind.cardNumber;
    if (_looksHighEntropy(trimmed)) return SensitiveKind.highEntropy;

    return null;
  }

  static bool isSensitive(String content) => classify(content) != null;

  /// A preview safe to show in a list: enough to recognise, not enough to use.
  ///
  /// Keeps the first and last few characters so the owner can tell two secrets
  /// apart without revealing either.
  static String mask(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= 8) return '•' * trimmed.length.clamp(4, 8);

    final head = trimmed.substring(0, 4);
    final tail = trimmed.substring(trimmed.length - 3);
    return '$head••••••••$tail';
  }

  /// True when [content] carries a card number that passes the Luhn check.
  ///
  /// Luhn matters: without it every 16-digit order reference and tracking
  /// number would be masked as a card.
  static bool _looksLikeCard(String content) {
    for (final match in _cardCandidate.allMatches(content)) {
      final digits = match.group(0)!.replaceAll(RegExp(r'[ -]'), '');
      if (digits.length < 13 || digits.length > 19) continue;
      if (_passesLuhn(digits)) return true;
    }
    return false;
  }

  static bool _passesLuhn(String digits) {
    var sum = 0;
    var double = false;

    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (d < 0 || d > 9) return false;

      if (double) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      double = !double;
    }
    return sum % 10 == 0;
  }

  /// A single long run of mixed characters with no whitespace.
  ///
  /// The catch-all for passwords and unrecognised keys. Requires real variety
  /// and a decent spread of distinct characters, so a long URL or a sentence
  /// does not trip it.
  static bool _looksHighEntropy(String content) {
    if (content.contains(RegExp(r'\s'))) return false;
    if (content.length < 20 || content.length > 200) return false;

    // A URL is long and mixed but is not a secret, and masking one would be
    // both wrong and annoying.
    if (RegExp(r'^[a-z]+://').hasMatch(content.toLowerCase())) return false;
    if (content.contains('@') && content.contains('.')) return false; // email

    final hasLower = RegExp(r'[a-z]').hasMatch(content);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(content);
    final hasDigit = RegExp(r'\d').hasMatch(content);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(content);

    final classes = [
      hasLower,
      hasUpper,
      hasDigit,
      hasSymbol,
    ].where((present) => present).length;
    if (classes < 3) return false;

    // Distinct characters relative to length: "abababab..." is long and mixed
    // but not random.
    final distinct = content.split('').toSet().length;
    return distinct >= content.length * 0.5;
  }
}

/// A one-time code lifted out of a verification message.
///
/// Copying the whole SMS is what people actually do; the code is the only part
/// they want. Surfacing it alone turns a paste-and-edit into one tap.
abstract class OneTimeCode {
  /// "Your verification code is 123456" — the keyword leads.
  static final RegExp _keywordThenCode = RegExp(
    r'\b(?:code|otp|pin|password|passcode|token|verification)\b[^0-9]{0,20}(\d{4,8})\b',
    caseSensitive: false,
  );

  /// "847291 is your CopyOnce code" — the code leads. Just as common, and the
  /// pattern most banks and Google use.
  static final RegExp _codeThenKeyword = RegExp(
    r'\b(\d{4,8})\b[^0-9]{0,40}?\b(?:code|otp|pin|passcode|verification)\b',
    caseSensitive: false,
  );

  static final RegExp _trailing = RegExp(r'(?:^|\s)(\d{4,8})(?:\s|$)');

  /// The code inside [content], or null when there is nothing code-shaped.
  ///
  /// Requires a nearby word like "code" or "OTP" unless the whole string is
  /// just digits — otherwise every price and street number becomes a code.
  static String? extract(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    // Already just the code.
    if (RegExp(r'^\d{4,8}$').hasMatch(trimmed)) return trimmed;

    // Too long to be a message carrying one.
    if (trimmed.length > 400) return null;

    final leading = _keywordThenCode.firstMatch(trimmed);
    if (leading != null) return leading.group(1);

    final trailing = _codeThenKeyword.firstMatch(trimmed);
    if (trailing != null) return trailing.group(1);

    // A short message with exactly one number that looks like a code.
    if (trimmed.length <= 160) {
      final numbers = _trailing
          .allMatches(trimmed)
          .map((m) => m.group(1)!)
          .toList();
      if (numbers.length == 1 &&
          RegExp(
            r'\b(verify|verification|confirm|authenticate|login|sign)',
            caseSensitive: false,
          ).hasMatch(trimmed)) {
        return numbers.first;
      }
    }

    return null;
  }
}
