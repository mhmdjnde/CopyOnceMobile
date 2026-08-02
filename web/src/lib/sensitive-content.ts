/**
 * Recognises copied text that looks like a secret.
 *
 * People copy passwords, tokens, and card numbers constantly — that is what a
 * password manager is for. CopyOnce carries whatever is on the clipboard, so
 * without this a secret is shown in full in a list that may be open on a screen
 * someone else can see.
 *
 * The rules are deliberately conservative. A false positive costs a click to
 * reveal; a false negative shows a live API key to the room. Where those trade
 * off, this leans towards masking.
 *
 * A rule-for-rule mirror of lib/utils/sensitive_content.dart. The parity test in
 * sensitive-content.test.ts keeps the two honest.
 */

export type SensitiveKind =
  | "privateKey"
  | "apiToken"
  | "jwt"
  | "cardNumber"
  | "highEntropy";

/** Named for what the user would call it, not for how it was detected. */
export const SENSITIVE_LABELS: Record<SensitiveKind, string> = {
  privateKey: "Private key",
  apiToken: "API key",
  jwt: "Access token",
  cardNumber: "Card number",
  highEntropy: "Possible password",
};

/** Token shapes published by the providers, so a match is a fact not a guess. */
const TOKEN_PATTERNS: RegExp[] = [
  /\bsk-[A-Za-z0-9]{20,}/, // OpenAI
  /\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}/, // Stripe
  /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}/, // GitHub
  /\bgithub_pat_[A-Za-z0-9_]{50,}/, // GitHub fine-grained
  /\bAKIA[0-9A-Z]{16}\b/, // AWS access key id
  /\bASIA[0-9A-Z]{16}\b/, // AWS temporary key id
  /\bAIza[0-9A-Za-z_-]{35}\b/, // Google API key
  /\bya29\.[0-9A-Za-z_-]{20,}/, // Google OAuth
  /\bxox[baprs]-[0-9A-Za-z-]{10,}/, // Slack
  /\bglpat-[0-9A-Za-z_-]{20,}/, // GitLab
  /\bsbp_[0-9a-f]{40,}/, // Supabase
  /\bnpm_[A-Za-z0-9]{36}\b/, // npm
];

const PRIVATE_KEY = /-----BEGIN [A-Z ]*PRIVATE KEY-----/;
const JWT = /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/;
const CARD_CANDIDATE = /\b(?:\d[ -]?){12,18}\d\b/g;

/** What kind of secret this looks like, or null for ordinary content. */
export function classifySensitive(content: string): SensitiveKind | null {
  const trimmed = content.trim();
  if (!trimmed) return null;

  if (PRIVATE_KEY.test(trimmed)) return "privateKey";
  if (JWT.test(trimmed)) return "jwt";
  if (TOKEN_PATTERNS.some((p) => p.test(trimmed))) return "apiToken";
  if (looksLikeCard(trimmed)) return "cardNumber";
  if (looksHighEntropy(trimmed)) return "highEntropy";

  return null;
}

export function isSensitive(content: string): boolean {
  return classifySensitive(content) !== null;
}

/**
 * A preview safe to show in a list: enough to recognise, not enough to use.
 *
 * Keeps the first and last few characters so the owner can tell two secrets
 * apart without revealing either.
 */
export function maskSensitive(content: string): string {
  const trimmed = content.trim();
  if (trimmed.length <= 8) {
    return "•".repeat(Math.min(Math.max(trimmed.length, 4), 8));
  }
  return `${trimmed.slice(0, 4)}••••••••${trimmed.slice(-3)}`;
}

/**
 * True when the content carries a card number that passes the Luhn check.
 *
 * Luhn matters: without it every 16-digit order reference and tracking number
 * would be masked as a card.
 */
function looksLikeCard(content: string): boolean {
  CARD_CANDIDATE.lastIndex = 0;
  for (const match of content.matchAll(CARD_CANDIDATE)) {
    const digits = match[0].replace(/[ -]/g, "");
    if (digits.length < 13 || digits.length > 19) continue;
    if (passesLuhn(digits)) return true;
  }
  return false;
}

function passesLuhn(digits: string): boolean {
  let sum = 0;
  let double = false;

  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48;
    if (d < 0 || d > 9) return false;

    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

/**
 * A single long run of mixed characters with no whitespace.
 *
 * The catch-all for passwords and unrecognised keys. Requires real variety and
 * a decent spread of distinct characters, so a long URL or a sentence does not
 * trip it.
 */
function looksHighEntropy(content: string): boolean {
  if (/\s/.test(content)) return false;
  if (content.length < 20 || content.length > 200) return false;

  // A URL is long and mixed but is not a secret, and masking one would be both
  // wrong and annoying.
  if (/^[a-z]+:\/\//i.test(content)) return false;
  if (content.includes("@") && content.includes(".")) return false; // email

  const classes = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((p) =>
    p.test(content),
  ).length;
  if (classes < 3) return false;

  const distinct = new Set(content).size;
  return distinct >= content.length * 0.5;
}

/**
 * A one-time code lifted out of a verification message.
 *
 * Copying the whole SMS is what people actually do; the code is the only part
 * they want. Surfacing it alone turns a paste-and-edit into one click.
 */
const KEYWORD_THEN_CODE =
  /\b(?:code|otp|pin|password|passcode|token|verification)\b[^0-9]{0,20}(\d{4,8})\b/i;

/** "847291 is your CopyOnce code" — the form most banks and Google use. */
const CODE_THEN_KEYWORD =
  /\b(\d{4,8})\b[^0-9]{0,40}?\b(?:code|otp|pin|passcode|verification)\b/i;

const STANDALONE_NUMBER = /(?:^|\s)(\d{4,8})(?:\s|$)/g;

export function extractOneTimeCode(content: string): string | null {
  const trimmed = content.trim();
  if (!trimmed) return null;

  // Already just the code.
  if (/^\d{4,8}$/.test(trimmed)) return trimmed;

  // Too long to be a message carrying one.
  if (trimmed.length > 400) return null;

  const leading = trimmed.match(KEYWORD_THEN_CODE);
  if (leading) return leading[1];

  const trailing = trimmed.match(CODE_THEN_KEYWORD);
  if (trailing) return trailing[1];

  // A short message with exactly one number and a verification-shaped verb.
  if (trimmed.length <= 160) {
    STANDALONE_NUMBER.lastIndex = 0;
    const numbers = [...trimmed.matchAll(STANDALONE_NUMBER)].map((m) => m[1]);
    if (
      numbers.length === 1 &&
      /\b(verify|verification|confirm|authenticate|login|sign)/i.test(trimmed)
    ) {
      return numbers[0];
    }
  }

  return null;
}
