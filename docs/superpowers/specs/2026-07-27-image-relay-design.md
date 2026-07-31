# Image relay — design

Date: 2026-07-27
Status: approved, in implementation

## What this is

Images become a fourth thing CopyOnce carries between a user's own devices.
They are a **relay, not a shelf**: an image exists only long enough to reach
every device on the account.

CopyOnce is not a drive. The product is direct connection between your own
devices, so an image that has already arrived everywhere has no reason to keep
existing. That principle, not the free-tier budget, is what shapes this design —
though it happens to make the free tier comfortable too.

## Lifecycle

An image is deleted at whichever comes first:

1. **Every registered device has fetched it.** The uploading device counts as
   delivered at upload time, so a single-device account reaps immediately.
2. **24 hours after upload.** A hard backstop for devices that never come
   online, so nothing can outlive the promise.

### What "fetched" means

**Downloading the full-resolution original**, which happens when the image is
opened. Seeing a thumbnail in the list is explicitly *not* receipt.

This distinction is the difference between a working feature and a trap. If a
thumbnail scrolling past counted as delivery, an image would be reaped moments
after appearing on the second device — before the user had any chance to save
it at full resolution. Requiring the original means the relay releases the image
only once a device has actually taken what it came for.

The consequence, which the UI states plainly rather than hiding: opening an
image on the last device that needed it starts its deletion. The viewer
therefore keeps the bytes it downloaded in memory, and the save button reuses
them rather than re-fetching — otherwise saving could fail on an image the user
is looking at.

Deletion is never partial. The file goes, then the row goes — in that order, for
reasons in "The orphan rule" below.

## Storage layout

Images live in Supabase Storage, not in `clipboard_items.content`. Three reasons,
in order of how decisive they are:

1. `watchItems()` uses Postgres realtime `.stream()`, which pushes the **entire
   row** to every subscribed device on every change. Image bytes in `content`
   would mean full images streaming over the websocket continuously.
2. `content` caps at 100,000 characters — about 73KB after base64. A single
   screenshot does not fit.
3. The free tier gives 500MB of database against 1GB of storage, and base64
   inflates payloads by a third. The scarce resource would be the wrong one.

Bucket `clipboard-media`, private. Two objects per image:

```
{user_id}/{item_id}/full.{ext}     original bytes, untouched
{user_id}/{item_id}/thumb.jpg      ~400px long edge, for the list
```

Thumbnails are lossy JPEG rather than WebP. The `image` package encodes WebP
*losslessly only*, which for a photograph produces a file several times larger
than a quality-78 JPEG — the opposite of what a thumbnail is for. Verified
against the package source, not assumed.

The list renders thumbnails only. The download button fetches `full`, which is
byte-identical to what was picked — "full resolution" means the original file,
not a re-encode. Deleting an image removes the whole `{user_id}/{item_id}/`
prefix, so a thumbnail can never outlive its original.

### On EXIF

The original is stored untouched, which preserves EXIF — including GPS. This is
deliberate: the image travels only between devices on one account, never leaves
it, and a re-encode would break the "full resolution" guarantee. The generated
thumbnail drops EXIF as a side effect of re-encoding.

## Limits

| Limit | Value | Enforced by |
|---|---|---|
| Live images per user | 10 | `BEFORE INSERT` trigger, errcode 54000 |
| Bytes per image | 10 MB | Bucket `file_size_limit` + column check |
| MIME types | jpeg, png, webp, gif, heic | Bucket `allowed_mime_types` |

**No monthly quota and no reset job.** With 24-hour expiry the live count is
self-healing, so a concurrent cap bounds storage without a counter table, a reset
schedule, or the "burn ten on the 2nd, locked out until the 1st" failure mode.

SVG is excluded on purpose — it can carry script, and clipboard content is
untrusted input.

## The orphan rule

Deleting a row from `clipboard_items` does **not** delete the file in Storage.
Get this backwards and orphaned objects accumulate invisibly until the bucket is
full of files nothing references.

So the ordering is fixed everywhere, with no exceptions:

> **Delete the storage object first. Delete the row second.**

If the file delete succeeds and the row delete fails, the next sweep retries and
`remove()` is idempotent — harmless. The reverse leaks a file permanently, with
nothing left pointing at it to find it again.

Postgres cannot delete from Storage. So no trigger ever deletes a file: the
delivery trigger only collapses `expires_at` to `now()`, marking the image for
the reaper. **One code path performs file deletion**, which is what makes the
ordering rule enforceable.

## The reaper, in two tiers

**Tier 1 — client backstop.** On launch, each client removes its own account's
expired images through the SDK, under RLS. Works with no deployment, so the
feature is correct from day one. Limitation: only runs when someone opens the
app.

**Tier 2 — scheduled `reap-media` Edge Function.** `pg_cron` + `pg_net` call it
every 5 minutes with the service role. Deletes expired images for *all* users
regardless of app activity, and sweeps orphans. This is what makes the 24-hour
guarantee real rather than best-effort.

Tier 1 stays after tier 2 ships, because free-tier projects pause after ~7 days
of inactivity and cron does not run while paused.

## Security

Storage policies gate on `(storage.foldername(name))[1] = auth.uid()::text`
**and `has_required_assurance()`**.

The second condition matters more than it looks. `clipboard_items` already
requires assurance level 2 for accounts with a verified TOTP factor, but Storage
policies are evaluated separately. Without the same check, someone holding only
the password could read images through the Storage API while the UI blocks them —
making 2FA cosmetic for the most sensitive content type in the app.

Signed URLs, short expiry, no public bucket. Image bytes and storage paths never
enter logs or error strings, consistent with `ClipboardFailure`'s existing rule.

## Pinning

Images cannot be pinned. `prune_expired_clipboard_items` exempts pinned rows, so
a pinnable image would be a user-visible hole in the 24-hour guarantee. The
guarantee is absolute or it is not a guarantee.

## Out of scope

**Automatic screenshot capture.** Considered and dropped. Both platforms make it
either impossible or hostile: iOS gives no background screenshot access at all,
and Android would need a persistent foreground service plus MediaStore
observation, draining battery and demanding permissions disproportionate to the
benefit. Manual upload only.

## Testing constraint

iOS cannot be built or verified on the development machine (Linux; iOS requires
macOS and Xcode). Mitigation: pure-Dart packages are preferred over native ones
wherever a choice exists, so behavior cannot silently diverge between platforms.
The `ios/` scaffold and `Info.plist` entries are written correctly but remain
**unverified on device** and need a Mac or CI runner before release.
