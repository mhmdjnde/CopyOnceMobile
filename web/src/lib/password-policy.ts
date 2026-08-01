/**
 * The password rules CopyOnce enforces, in one place.
 *
 * A rule-for-rule mirror of lib/utils/password_policy.dart. The two files are
 * one policy expressed twice: if a rule or a message changes in one, it changes
 * in the other, or the same password is accepted on your laptop and refused on
 * your phone.
 *
 * The server stays the authority — a client pass is never authorization.
 *
 * Composition rules are deliberately modest. Length carries most of the real
 * strength, and demanding exotic symbols pushes people toward `Password1!` and
 * a sticky note.
 */

/** Must match PasswordPolicy.minLength in Dart and the project's Auth setting. */
export const MIN_PASSWORD_LENGTH = 8;

export type PasswordRule =
  | "length"
  | "lowercase"
  | "uppercase"
  | "digit"
  | "notCommon"
  | "notEmailLike";

/** Every rule, in the order the checklist shows them. */
export const PASSWORD_RULES: PasswordRule[] = [
  "length",
  "lowercase",
  "uppercase",
  "digit",
  "notCommon",
  "notEmailLike",
];

/** Checklist wording, phrased as the goal rather than the failure. */
export const RULE_LABELS: Record<PasswordRule, string> = {
  length: `At least ${MIN_PASSWORD_LENGTH} characters`,
  lowercase: "A lowercase letter",
  uppercase: "An uppercase letter",
  digit: "A number",
  notCommon: "Not a commonly used password",
  notEmailLike: "Different from your email address",
};

/** Error wording, phrased as the single next thing to do. */
export const RULE_MESSAGES: Record<PasswordRule, string> = {
  length: `Use at least ${MIN_PASSWORD_LENGTH} characters.`,
  lowercase: "Add a lowercase letter.",
  uppercase: "Add an uppercase letter.",
  digit: "Add a number.",
  notCommon: "That password is too common to be safe.",
  notEmailLike: "Do not reuse your email address.",
};

export type PasswordStrength = "empty" | "weak" | "fair" | "good" | "strong";

export const STRENGTH_LABELS: Record<PasswordStrength, string> = {
  empty: "",
  weak: "Weak",
  fair: "Fair",
  good: "Good",
  strong: "Strong",
};

/**
 * Passwords common enough that a credential-stuffing list would try them within
 * the first handful of guesses. A short local list, not a substitute for the
 * server's leaked-password check — it catches the obvious cases before a round
 * trip.
 */
const COMMON_PASSWORDS = new Set([
  "password", "passw0rd", "password1", "password123",
  "qwerty", "qwerty123", "letmein", "welcome", "welcome1",
  "admin", "administrator", "iloveyou", "monkey", "dragon",
  "football", "baseball", "sunshine", "princess", "trustno1",
  "abc123", "abcd1234", "123456", "1234567", "12345678",
  "123456789", "1234567890", "111111", "000000",
  "copyonce", "clipboard",
]);

export interface PasswordAssessment {
  satisfied: Set<PasswordRule>;
  strength: PasswordStrength;
  /** True when every rule is met and the password may be submitted. */
  isAcceptable: boolean;
  /** Rules still outstanding, in declaration order. */
  unmet: PasswordRule[];
}

/** Checks `password`, optionally against the `email` it will protect. */
export function assessPassword(
  password: string,
  email?: string,
): PasswordAssessment {
  const satisfied = new Set<PasswordRule>();

  if (!password) {
    return {
      satisfied,
      strength: "empty",
      isAcceptable: false,
      unmet: [...PASSWORD_RULES],
    };
  }

  if (password.length >= MIN_PASSWORD_LENGTH) satisfied.add("length");
  if (/[a-z]/.test(password)) satisfied.add("lowercase");
  if (/[A-Z]/.test(password)) satisfied.add("uppercase");
  if (/\d/.test(password)) satisfied.add("digit");
  if (!isCommon(password)) satisfied.add("notCommon");
  if (!resemblesEmail(password, email)) satisfied.add("notEmailLike");

  const unmet = PASSWORD_RULES.filter((r) => !satisfied.has(r));

  return {
    satisfied,
    strength: strengthOf(password, satisfied),
    isAcceptable: unmet.length === 0,
    unmet,
  };
}

/**
 * Null when acceptable, otherwise the first unmet requirement phrased as an
 * instruction — so the user is told one concrete thing to do, not a list.
 */
export function validatePassword(
  password: string,
  email?: string,
): string | null {
  if (!password) return "Enter a password.";
  const assessment = assessPassword(password, email);
  if (assessment.isAcceptable) return null;
  return RULE_MESSAGES[assessment.unmet[0]];
}

function isCommon(password: string): boolean {
  const lower = password.toLowerCase();
  if (COMMON_PASSWORDS.has(lower)) return true;
  // Catch `myPassword123` and friends, without letting a short entry like
  // `abc123` condemn every password that happens to contain it.
  return [...COMMON_PASSWORDS].some(
    (common) => common.length >= 6 && lower.includes(common),
  );
}

function resemblesEmail(password: string, email?: string): boolean {
  const address = email?.trim().toLowerCase() ?? "";
  if (!address) return false;

  const lower = password.toLowerCase();
  if (lower === address) return true;

  const localPart = address.split("@")[0];
  // Only meaningful for local parts long enough to be distinctive.
  return localPart.length >= 4 && lower.includes(localPart);
}

/** Blends length with variety: length dominates, variety breaks ties. */
function strengthOf(
  password: string,
  satisfied: Set<PasswordRule>,
): PasswordStrength {
  // A password failing a hard rule never reads above weak, so the meter cannot
  // say "Strong" next to a blocking error.
  if (!satisfied.has("notCommon") || !satisfied.has("notEmailLike")) {
    return "weak";
  }

  let score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (/[^A-Za-z0-9]/.test(password)) score++;
  if (
    satisfied.has("lowercase") &&
    satisfied.has("uppercase") &&
    satisfied.has("digit")
  ) {
    score++;
  }

  if (score <= 1) return "weak";
  if (score === 2) return "fair";
  if (score === 3) return "good";
  return "strong";
}
