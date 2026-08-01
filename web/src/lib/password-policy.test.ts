/**
 * Guards the web password policy against drifting from the Flutter one.
 *
 * The two clients enforce the same rules in two languages, and a mismatch is
 * invisible until someone sets a password on their laptop that their phone then
 * refuses. This file reads the Dart source and asserts the numbers still agree,
 * which is cheaper than remembering.
 *
 * Run with: node --test src/lib/password-policy.test.ts
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { strict as assert } from "node:assert";
import { test } from "node:test";

import { MIN_PASSWORD_LENGTH, assessPassword, validatePassword } from "./password-policy";
import { VERIFICATION_CODE_LENGTH, AUTHENTICATOR_CODE_LENGTH } from "./types";

const REPO = join(import.meta.dirname, "..", "..", "..");

function dartSource(relative: string): string {
  return readFileSync(join(REPO, relative), "utf8");
}

test("minimum length matches the Flutter client", () => {
  const dart = dartSource("lib/utils/password_policy.dart");
  const match = dart.match(/static const int minLength = (\d+);/);
  assert.ok(match, "could not find minLength in password_policy.dart");
  assert.equal(
    Number(match[1]),
    MIN_PASSWORD_LENGTH,
    "web and Flutter disagree on the minimum password length",
  );
});

test("emailed code length matches the Flutter client", () => {
  const dart = dartSource("lib/utils/validators.dart");
  const match = dart.match(/static const int verificationCodeLength = (\d+);/);
  assert.ok(match, "could not find verificationCodeLength in validators.dart");
  assert.equal(
    Number(match[1]),
    VERIFICATION_CODE_LENGTH,
    "web and Flutter disagree on the emailed code length",
  );
});

test("authenticator code length matches the Flutter client", () => {
  const dart = dartSource("lib/utils/validators.dart");
  const match = dart.match(/static const int authenticatorCodeLength = (\d+);/);
  assert.ok(match, "could not find authenticatorCodeLength in validators.dart");
  assert.equal(
    Number(match[1]),
    AUTHENTICATOR_CODE_LENGTH,
    "web and Flutter disagree on the authenticator code length",
  );
});

test("the two code lengths are genuinely different", () => {
  // Conflating these is what produced the original bug: the emailed code is
  // configurable and set to 8, while TOTP is fixed at 6 by its standard.
  assert.notEqual(VERIFICATION_CODE_LENGTH, AUTHENTICATOR_CODE_LENGTH);
});

test("accepts a password at exactly the minimum", () => {
  assert.equal(validatePassword("Abcdef1g"), null);
  assert.equal("Abcdef1g".length, MIN_PASSWORD_LENGTH);
});

test("names the length rule first when several are unmet", () => {
  assert.equal(validatePassword("ab"), "Use at least 8 characters.");
});

test("asks for one specific thing when only that is missing", () => {
  assert.equal(validatePassword("abcdefg1"), "Add an uppercase letter.");
  assert.equal(validatePassword("ABCDEFG1"), "Add a lowercase letter.");
  assert.equal(validatePassword("Abcdefgh"), "Add a number.");
});

test("rejects common passwords and email-derived passwords", () => {
  assert.equal(
    validatePassword("Password123"),
    "That password is too common to be safe.",
  );
  assert.equal(
    validatePassword("Jndeishere1", "jndeishere@example.com"),
    "Do not reuse your email address.",
  );
});

test("a blocking failure never reads better than weak", () => {
  assert.equal(assessPassword("Password123").strength, "weak");
});

test("strength grows with length", () => {
  const short = assessPassword("Abcdef1g").strength;
  const long = assessPassword("Abcdef1gHijklmno").strength;
  assert.notEqual(short, long);
});

test("empty input is reported plainly", () => {
  assert.equal(validatePassword(""), "Enter a password.");
});
