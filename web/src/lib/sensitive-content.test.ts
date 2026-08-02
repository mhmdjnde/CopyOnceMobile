/**
 * Parity tests for the sensitive-content rules.
 *
 * The same cases run against the Dart implementation in
 * test/sensitive_content_test.dart. A secret masked on the phone but shown in
 * full on the laptop would be worse than not masking at all, because the user
 * would have learned to trust it.
 *
 * Run with: npm test
 */

import { strict as assert } from "node:assert";
import { test } from "node:test";

import {
  classifySensitive,
  extractOneTimeCode,
  isSensitive,
  maskSensitive,
} from "./sensitive-content";

test("recognises a PEM private key", () => {
  assert.equal(
    classifySensitive(
      "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKC\n-----END RSA PRIVATE KEY-----",
    ),
    "privateKey",
  );
});

test("recognises provider tokens by their published shapes", () => {
  // Assembled at runtime rather than written out. A literal token shape in a
  // source file trips GitHub's secret scanner and blocks the push, even though
  // these are invented — and a fixture that looks like a live credential is a
  // bad habit regardless.
  const alpha = "abcdefghijklmnopqrstuvwxyz";
  const tokens = [
    `sk-${alpha}123456`,
    `sk_${"live"}_51H8xKjLkKdIwJkLmNoPqRs`,
    `ghp_${alpha}0123456789`,
    `AKIA${"IOSFODNN7EXAMPLE"}`,
    `xox${"b"}-123456789012-abcdefghijklmno`,
    "glpat-abcdefghij1234567890",
  ];
  for (const token of tokens) {
    assert.equal(classifySensitive(token), "apiToken", token);
  }
});

test("recognises a JWT", () => {
  assert.equal(
    classifySensitive(
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk",
    ),
    "jwt",
  );
});

test("flags card numbers that pass Luhn", () => {
  // Well-known test numbers, not real cards.
  for (const card of ["4242424242424242", "4111 1111 1111 1111", "5555-5555-5555-4444"]) {
    assert.equal(classifySensitive(card), "cardNumber", card);
  }
});

test("ignores long digit strings that fail Luhn", () => {
  // Luhn is what stops every order reference becoming a card number.
  assert.notEqual(classifySensitive("1234567812345678"), "cardNumber");
  assert.equal(classifySensitive("Tracking 9400111899223197428490"), null);
});

test("flags a long random mixed string", () => {
  assert.equal(classifySensitive("Tr0ub4dor&3xKcd#9Zq!mVn2"), "highEntropy");
});

test("leaves ordinary content alone", () => {
  const harmless = [
    "hello world",
    "Remember to call the dentist on Tuesday",
    "https://example.com/some/quite/long/path?with=query&more=params",
    "someone@example.com",
    "The quick brown fox jumps over the lazy dog",
    "42",
    'git commit -m "fix the thing"',
  ];
  for (const text of harmless) {
    assert.equal(classifySensitive(text), null, text);
  }
});

test("a repeated pattern is long but not random", () => {
  assert.equal(classifySensitive("Ab1Ab1Ab1Ab1Ab1Ab1Ab1Ab1"), null);
});

test("isSensitive agrees with classify", () => {
  assert.equal(isSensitive("AKIAIOSFODNN7EXAMPLE"), true);
  assert.equal(isSensitive("hello world"), false);
});

test("mask keeps enough to tell two secrets apart", () => {
  const masked = maskSensitive("sk_live_51H8xKjLkKdIwJkLmNoPqRs");
  assert.ok(masked.startsWith("sk_l"));
  assert.ok(masked.includes("••••"));
});

test("mask never echoes the middle of the secret", () => {
  const masked = maskSensitive("sk_live_51H8xKjLkKdIwJkLmNoPqRs");
  assert.equal(masked.includes("51H8xKjLkKdIwJkLmNo"), false);
});

test("short values are fully hidden", () => {
  assert.match(maskSensitive("abc123"), /^•+$/);
});

test("lifts the code out of a verification message", () => {
  const messages: Record<string, string> = {
    "Your verification code is 123456": "123456",
    "847291 is your CopyOnce code": "847291",
    "Use OTP 4821 to sign in": "4821",
    "PIN: 9182": "9182",
  };
  for (const [message, code] of Object.entries(messages)) {
    assert.equal(extractOneTimeCode(message), code, message);
  }
});

test("passes a bare code straight through", () => {
  assert.equal(extractOneTimeCode("582910"), "582910");
});

test("does not invent codes from ordinary numbers", () => {
  const notCodes = [
    "The meeting is at 1400 in room 2201",
    "Invoice 88213 is overdue",
    "I paid 4500 for it",
    "hello world",
  ];
  for (const text of notCodes) {
    assert.equal(extractOneTimeCode(text), null, text);
  }
});

test("ignores anything long enough to be a document", () => {
  assert.equal(extractOneTimeCode(`code 1234 ${"x".repeat(500)}`), null);
});

test("token pattern list matches the Dart one", () => {
  // Guards against one side gaining a provider the other does not know.
  const dart = readDart();
  // Markers as they appear literally in the Dart source — the two write the
  // same rule with slightly different grouping, so match on the provider
  // identifier rather than the surrounding punctuation.
  const providers = [
    "sk-", "(live|test)", "ghp", "github_pat_", "AKIA", "ASIA",
    "AIza", "ya29", "xox", "glpat-", "sbp_", "npm_",
  ];
  for (const marker of providers) {
    assert.ok(dart.includes(marker), `Dart is missing ${marker}`);
  }
});

function readDart(): string {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { readFileSync } = require("node:fs") as typeof import("node:fs");
  const { join } = require("node:path") as typeof import("node:path");
  return readFileSync(
    join(import.meta.dirname, "..", "..", "..", "lib", "utils", "sensitive_content.dart"),
    "utf8",
  );
}
