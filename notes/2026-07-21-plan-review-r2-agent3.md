# Plan Review — Product / Integration / UX Reviewer (r2, agent3)

Note: still an iMessage→Spotify daemon, not a social friend-list app; reviewed through the
Product/Integration/UX lens (end-to-end flow, front↔back API-contract consistency, real error
paths, cross-section consistency).

## Prior-fix verification
- **C1 (chat.db reader)** — FIXED. §2 uses `file:...?mode=ro`, fresh connection per poll, explicit "do not use `immutable=1`".
- **C2 (watermark advances only past successful adds; failures→retry)** — mechanically present (arch §32, §5 77–78) but introduces a new contract inconsistency (see Must-fix #1).
- **C3 (first-run seed MAX(ROWID))** — FIXED. §1 46 + M3 124.
- **M1 (playlist-read-private scope)** — FIXED. §4 71 with rationale.

## Critical
- none

## Must-fix
- **Watermark advance rule is under-defined and conflicts with the retry queue (C2 regression).** §5 "Watermark discipline" (line 78) + M3 (line 125) say advance "only past messages whose add succeeded," yet failures also go to a "durable pending/retry queue." These are two recovery mechanisms doing the same job. Taken literally: (a) the vast majority of messages (no Spotify link, `is_from_me=1` filtered out, dedup-skipped) never produce a successful add, so the watermark stalls at the *last link that was added* and every poll re-scans/re-parses the entire tail of ordinary chatter; (b) with both mechanisms, a failed message is simultaneously held-back-by-watermark AND queued, so later already-succeeded messages get re-read every poll (only the seen-set saves them). Fix: define the watermark to advance past every *terminally resolved* message — no link, filtered, dedup-skip, add-success, **or enqueued to the retry queue** — and let the durable queue own retries. Choose queue-owns-retries OR watermark-holds-back, not both; update §5 and M3's done-criteria to match.
- **OAuth callback receiver is still undefined (r1 unresolved).** §4 still says only "one-time browser login"; Setup step 2 (line 135) references redirect `http://127.0.0.1:PORT/callback`, but no component captures the redirect. PKCE requires a loopback HTTP listener to receive the auth `code`. Fix: add a local callback-server responsibility to `spotify.py` (or a small auth module) in Components.
- **Config still missing `client_id` and `redirect_uri`/`port` (r1 unresolved).** Setup steps 2–3 depend on a client ID and redirect URI, but §1 Config lists none. Section-to-section contract gap. Fix: add `client_id` and `redirect_uri`/`callback_port` to §1 Config.

## Medium
- **Poison-message / permanent-failure has no dead-letter (new, from C2).** A non-retryable add failure (deleted/region-locked track, malformed URI, 4xx) is retried forever; under the watermark-hold design it also blocks the watermark → unbounded re-scan of a growing tail. §5/§78. Fix: define a max-retry / dead-letter drop so a permanently-failing URI is abandoned (logged) and the pipeline advances.
- **`only_from_others=true` default conflicts with stated test flow (r1 unresolved).** §1 44 skips `is_from_me=1`; M3 (line 125) is verified by "text a link → it lands." Self-texted links are filtered, so the acceptance test fails with defaults. Fix: verify via a second handle, or set `only_from_others=false` for M1/M3.
- **`dedup_liked_songs=true` default may drop wanted songs (r1 unresolved).** §1 48 + Dedup strategy skip any incoming track already Liked even if absent from the friend playlist — surprising for a "friend playlist." Fix: reconsider default, or scope dedup to playlist-only and document the trade-off.
- **No defined behavior when auth fails unattended (r1 unresolved).** §5 daemon loop has no path for a revoked/expired refresh token; adds silently stop while the daemon looks "running." Fix: define a re-auth/notify path in the daemon loop.

## Low
- **No user-facing success/failure feedback (r1 unresolved).** For an "ambient, zero-tap" product the only signal is a log file (§5 79). User can't tell it works or stopped. Fix: minimal macOS notification on add/failure, or explicitly accept log-only for MVP and defer menubar status to v2.

## Impl-note
- `mode=ro` WAL visibility (new): a read-only connection must be able to open `-wal`/`-shm` to see committed rows Messages just wrote; verify during M1 (§2).
- Handle normalization for `allowed_handles` (phone vs. email, multi-match) — implementation detail (§1).
- Playlist dedup cache staleness between periodic refreshes if user edits playlists elsewhere; refresh cadence is tuning (Dedup strategy).
- Regex/`?si=` share-token stripping and `spotify:track:` URI edge cases (§3) — surface during coding.
