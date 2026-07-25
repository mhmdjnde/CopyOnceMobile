# Auth email templates

Supabase stores these in the project, not in this repo, so they live here as the
source of truth and get pasted into the dashboard.

## Prerequisite: custom SMTP

Template editing is locked until the project has custom SMTP. Until then the
Subject and Body fields are read-only and the built-in email service sends
Supabase's default link-only email, which the app's code screen cannot use.

Set it up under **Authentication → Emails → SMTP Settings**. Any provider works;
free tiers that cover development: Resend (3k/month), Brevo (300/day).

### Gmail SMTP (development only)

Google caps sending at roughly 500 messages/day and throttles bursts, so this is
fine for testing the flow and wrong for real users. App passwords also require
2-Step Verification on the sending account — enable that first or the option
does not appear.

| Field | Value |
| --- | --- |
| Sender email | the sending Gmail address (must match Username) |
| Sender name | `CopyOnce` |
| Host | `smtp.gmail.com` |
| Port | `465` |
| Username | the sending Gmail address |
| Password | the 16-character app password, entered by hand |

Never commit the app password. It is a credential for the whole mailbox, not
just for sending, so treat it like the mailbox login it is — and revoke it at
myaccount.google.com if it ever lands anywhere shared.

After saving, **Authentication → Rate Limits** still caps confirmation emails
per hour; raise it there if testing hits the ceiling.

## Applying a template

1. Dashboard → **Authentication → Emails → Templates**.
2. Pick the template below, switch Body to the **Source** tab.
3. Paste the file contents, set the Subject, and Save.

| File | Template | Subject |
| --- | --- | --- |
| `confirm_signup.html` | Confirm sign up | `Your CopyOnce verification code` |

The code stays out of the subject line on purpose: subjects show up in lock-screen
notifications and inbox previews, and the body already explains itself.

`confirm_signup.html` is also what Supabase sends on a resend of type `signup`,
so it covers both entry points: signing up, and signing in with an account whose
email was never verified.

Keep **Confirm email** enabled under Authentication → Sign In / Providers →
Email. That setting is what makes Supabase issue the code at all.

## Code length

The same Email settings page sets **Email OTP Length** (Supabase allows 6–10).
It must match `Validators.verificationCodeLength` in the app, which drives the
input's length limit, its validation message, and the auto-submit. This project
sends **8**. Change one and the code screen stops accepting real codes.
