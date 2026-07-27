# Plan Review Summary

**Plan:** `/Users/aaron/code/personal/Projects/friendList/PLAN.md` · **Rounds:** 2 · **Final revision:** none (no `revision:` frontmatter to bump)

Two review rounds converged: R1 upheld and fixed 4 issues; R2 verified those fixes held and found no surviving Critical/Must-fix. The plan is implementable as written, pending two small pre-build edits (see Remaining Issues).

## Issues Found & Fixed

### Round 1 (4 issues UPHELD & FIXED)
- **C1 (Critical) — chat.db reader `immutable=1`.** `immutable=1` on a live WAL database ignores the `-wal` sidecar and disables change detection, hiding recent messages and risking corrupt reads. **Fix:** drop `immutable=1`; use plain `mode=ro` and open a fresh read-only connection per poll.
- **C2 (Critical) — watermark advanced without add-success gate.** Loop persisted `last_seen` ROWID unconditionally, so a transient 401/429/5xx on add permanently and silently dropped that song. **Fix:** advance the ROWID watermark only past messages whose add succeeded; failed URIs go to a durable pending/retry queue.
- **C3 (Critical) — undefined initial cursor.** `last_seen` bootstrap value was undefined; the natural default (0) scans full history and mass-adds every link ever received on first run. **Fix:** on first run with no state, seed `last_seen = SELECT MAX(ROWID) FROM message` (start from "now").
- **M1 (Must-fix) — missing Spotify scope.** §4 scope list omitted `playlist-read-private`; reading owned private playlists for dedup would 403 → silent duplicate adds. **Fix:** add `playlist-read-private` to the §4 scope list.

### Round 1 dispositions (not fixed)
- **M2 (callback receiver) — DISMISSED:** PKCE loopback listener is an ordinary impl detail inside `spotify.py`'s stated responsibility; fails loudly at setup, never silently.
- **M5 (playlist ownership) — DISMISSED:** plan already says "scan every **owned** playlist"; filtering `/me/playlists` by `owner.id` via `GET /v1/me` is the faithful implementation. Opt-in, default off.
- **M3 (config home) — DOWNGRADED → Low:** `client_id`/`redirect_uri` must live somewhere but the gap surfaces loudly at build time, not silently.
- **M4 (attributedBody read/write race) — DOWNGRADED → Low:** split-commit claim asserted, not demonstrated; SQLite exposes rows only at commit. Kept as an M1 verification note; C2's fix covers residual risk.

### Round 2
- R1 fixes verified resolved (C1, C2, C3, M1-r1 all confirmed applied).
- All new/re-raised issues failed the judge — **no Critical or Must-fix survived**:
  - **C1 (re-raised, `mode=ro` WAL visibility) → Impl-note:** same-user daemon participates in the WAL shared-memory protocol and sees committed rows even under `mode=ro`; the row-hiding failure is specific to the already-banned `immutable=1`.
  - **M1 (watermark-hold vs retry-queue conflict) → Medium:** the two mechanisms are redundant, not conflicting; seen-set + API dedup keep re-scan and queue idempotent, so output stays correct.
  - **M2/M3/M4 — DISMISSED:** re-raises of R1 items (M4→settle-window, M5→ownership, M2→callback) with no new evidence.
  - **M5 (config) — stays Low:** pure severity re-escalation with no new reasoning; build-time-loud, never silent.

## Remaining Issues (noted, not fixed)

**Medium**
- **M1 watermark-rule wording (R2) → Medium:** rewrite the rule as "advance past every terminally-resolved row (no-link/filtered/dedup-skip/added/enqueued); the durable retry queue solely owns failures, bounded attempts → dead-letter." A permanently-poisoned row otherwise stalls the watermark and grows the tail re-scan unbounded — robustness/spec-hygiene, not data loss.
- State-file schema / retry-queue not in state model — specify `{watermark ROWID, seen [{track_id, isrc}], pending [{uri, source_rowid, attempts}]}`.
- `allowed_handles` has no normalization contract (raw E.164 / email / short-code; one friend, many handles) — define canonicalization/aliasing.
- Group-chat capture & sender attribution unaddressed (LEFT JOIN handle resolves DMs only) — state scope or declare non-goal.
- PII contact handles in plaintext logs (§5 line 79, §6 line 82) — hash/truncate by default or gate behind a flag.
- Full Disk Access granted to shared `python3` is over-broad (Setup step 1) — grant to a dedicated venv wrapper.
- `only_from_others=true` default conflicts with M3 acceptance test (self-texts filtered) — use a 2nd handle or flip default for M1/M3.
- `dedup_liked_songs=true` default may silently drop wanted friend-sent songs absent from a friend playlist (§1 line 48) — reconsider or scope to playlist-only.
- No defined behavior when auth fails unattended (revoked/expired token → silent stop) — define re-auth/notify path.

**Low**
- **§1 Config `client_id` / `redirect_uri` (R2 M5, R1 M3) → Low:** add `client_id` + `redirect_uri`/`callback_port` as one line to §1 Config.
- Target-playlist dedup cache goes stale vs. other-device adds — note the window (line 92).
- Architecture diagram implies Liked Songs is an add target, contradicting §4 (line 30 vs 73) — clarify it is a dedup source only.
- Over-broad `playlist-modify-public` scope for a single private playlist (line 71) — drop (least-privilege).
- Persisted seen-set grows unbounded (§1 lines 46/102) — note cap/compaction.
- No user-facing success/failure feedback, log-only (§5 line 79) — add a macOS notification or accept for MVP.

## Implementation Notes

- **C1 WAL-read verification checkpoint:** confirm `mode=ro` fresh-per-poll connection reads uncheckpointed `-wal` rows on real chat.db during milestone M1; snapshot-copy of `chat.db`+`-wal`+`-shm` to temp is the documented fallback.
- **M2/M4 settle-window checkpoint:** the `attributedBody` late-landing scenario stays undemonstrated; M1's decode-against-real-chat.db milestone is where a true settle window would surface — add the localized fix (hold watermark on rows younger than N seconds) then if evidence appears.
- Retry-queue poison handling: max-attempts / dead-letter and backoff curve are tuning details.
- Batch-commit ordering (add → seen-set update → ROWID advance) for crash-safe at-least-once; resolve when wiring M3.
- Retry-queue entries need track name + sender handle at enqueue for "log every add" on retry success.
- Spotify `POST /playlists/{id}/tracks` has no server-side dedup; correctness relies wholly on local logic (optionally use `snapshot_id`).
- Playlist-cache staleness / refresh cadence and poll tuning values.
- launchd `KeepAlive` could overlap two instances writing `state_path` — single-writer guard.
- `typedstream`/`streamtyped` decode specifics across macOS versions (already under Risks).
- Regex `?si=` share-token stripping and `spotify:track:` URI edge cases (§3).

## Reviewer Personas Used

**Panel (opus), both rounds:**
- Systems Architect
- Backend & Privacy Specialist
- Product / Integration / UX Reviewer

**Adversarial validation (each round):**
- Devil's Advocate (opus)
- Judge / Referee (clear fable — `claude-fable-5`)
