import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Auth flows that need more than a single Supabase call to behave correctly.
 *
 * Mirrors lib/repositories/auth_repository.dart. Screens never match on server
 * error text — they read the outcome returned here.
 */

export type SignUpResult =
  | { status: "codeSent" }
  | { status: "signedIn" }
  | { status: "alreadyRegistered" };

export type SignInResult =
  | { status: "signedIn" }
  | { status: "needsTotp" }
  | { status: "needsEmailCode" }
  | { status: "failed"; message: string };

/**
 * Creates an account, refusing to pretend when the address is already taken.
 *
 * With email confirmation on, Supabase does not error on a duplicate — it
 * returns a hollow user so sign-up cannot be used to discover who has an
 * account. The tell is an empty identities list. Without this check the app
 * would ask for a code that was never sent, and the person would sit waiting
 * for an email that is never coming.
 */
export async function signUp(
  supabase: SupabaseClient,
  params: { email: string; password: string; displayName?: string },
): Promise<SignUpResult> {
  const { data, error } = await supabase.auth.signUp({
    email: params.email.trim(),
    password: params.password,
    options: {
      data: params.displayName?.trim() ? { display_name: params.displayName.trim() } : undefined,
    },
  });

  if (error) {
    // Some project configurations do error outright; treat both the same.
    if (
      error.code === "user_already_exists" ||
      /already registered|already been registered/i.test(error.message)
    ) {
      return { status: "alreadyRegistered" };
    }
    throw error;
  }

  if (data.session) return { status: "signedIn" };

  const identities = data.user?.identities;
  if (identities && identities.length === 0) {
    return { status: "alreadyRegistered" };
  }

  return { status: "codeSent" };
}

/**
 * Signs in, and reports what is still outstanding.
 *
 * Two things can be owed after a correct password. A second factor, because
 * Supabase issues a session at assurance level 1 before TOTP is verified and the
 * database returns no clipboard row below level 2. Or the emailed sign-up code,
 * when someone closed the tab before entering it — that account exists, so
 * registering again is not the answer; finishing the verification is.
 */
export async function signIn(
  supabase: SupabaseClient,
  params: { email: string; password: string },
): Promise<SignInResult> {
  const { error } = await supabase.auth.signInWithPassword({
    email: params.email.trim(),
    password: params.password,
  });

  if (error) {
    if (error.code === "email_not_confirmed" || /not confirmed/i.test(error.message)) {
      return { status: "needsEmailCode" };
    }
    return { status: "failed", message: friendlySignInError(error.message) };
  }

  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.nextLevel === "aal2" && aal.nextLevel !== aal.currentLevel) {
    return { status: "needsTotp" };
  }

  return { status: "signedIn" };
}

/** Emails a fresh sign-up code, invalidating the previous one. */
export async function resendSignUpCode(
  supabase: SupabaseClient,
  email: string,
): Promise<void> {
  const { error } = await supabase.auth.resend({
    type: "signup",
    email: email.trim(),
  });
  if (error) throw error;
}

/** Exchanges the emailed code for a session. */
export async function verifyEmailCode(
  supabase: SupabaseClient,
  params: { email: string; token: string },
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { error } = await supabase.auth.verifyOtp({
    email: params.email.trim(),
    token: params.token.trim(),
    type: "signup",
  });

  if (error) {
    return { ok: false, message: "That code was not accepted. Check it and try again." };
  }
  return { ok: true };
}

/**
 * Changes the password after proving the current one.
 *
 * Supabase lets a live session set a new password without re-entering the old
 * one, which means a borrowed unlocked laptop is enough to lock the owner out of
 * their own clipboard. Re-authenticating first closes that. The check reuses the
 * signed-in address, so a signed-out caller cannot reach it.
 */
export async function changePassword(
  supabase: SupabaseClient,
  params: { currentPassword: string; newPassword: string },
): Promise<{ ok: true } | { ok: false; message: string }> {
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const email = user?.email;
  if (!email) {
    return { ok: false, message: "Sign in again to change your password." };
  }

  const { error: reauthError } = await supabase.auth.signInWithPassword({
    email,
    password: params.currentPassword,
  });

  if (reauthError) {
    // Reported as a wrong current password rather than a generic failure, and
    // deliberately not distinguished from other sign-in errors.
    return { ok: false, message: "That is not your current password." };
  }

  if (params.currentPassword === params.newPassword) {
    return { ok: false, message: "Choose a password you have not used here before." };
  }

  const { error } = await supabase.auth.updateUser({ password: params.newPassword });
  if (error) return { ok: false, message: error.message };

  return { ok: true };
}

function friendlySignInError(message: string): string {
  if (/invalid login credentials/i.test(message)) {
    return "That email and password do not match an account.";
  }
  return message;
}
