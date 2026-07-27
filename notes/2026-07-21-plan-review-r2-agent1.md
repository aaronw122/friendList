# Plan Review R2 — Systems Architect (agent1)

Lens: structural soundness, data model, state/failure transitions, race conditions, missing
endpoint dependencies, cross-section API contract coherence.

## Verdict on round-1 fixes
- **C1 (drop `immutable=1`, fresh `mode=ro` per poll)** — partially fixed, but the replacement introduces a new WAL-visibility bug (see Critical below). Direction correct, mechanism unsafe.
- **C2 (advance watermark only past successful adds; failures → retry queue)** — intent applied, but the two recovery mechanisms as written contradict each other (see Must-fix) and it does not cover empty/no-link rows (see Must-fix on settle window).
- **C3 (seed `last_seen = MAX(ROWID)` first run)** — ✅ genuinely fixed (Config §1 line 46 + M3 line 124). No new issue.
- **M1 (add `playlist-read-private`)** — ✅ genuinely fixed (§4 line 71 with rationale).

## Critical
- **`mode=ro` alone cannot read a live WAL database → daemon either fails to open or silently misses the newest messages still in the `-wal` file (the exact rows it exists to catch).** Section *chat.db reader §2* (line 53). SQLite requires write access to the `-shm`/`-wal` sidecars to see WAL content; a pure `SQLITE_OPEN_READONLY` connection refuses that and falls back to the main db file only — the same "hides newly-arrived rows" failure that dropping `immutable=1` was meant to cure. Fix: specify a WAL-safe read path in the plan — open read-write but issue SELECT-only (never writing the db proper), OR snapshot-copy `chat.db`+`-wal`+`-shm` to a temp dir and read the copy — and drop the `mode=ro` requirement as the sole guarantee.

## Must-fix
- **Watermark-hold and retry-queue are two conflicting recovery mechanisms for the same failure.** Section *Daemon loop §5* (line 78) + *Architecture* (line 32). "watermark stops at the last fully-successful message" AND "failed URIs → durable retry queue" cannot both be the recovery: if the watermark holds, the failed row is re-scanned next poll and the queue is redundant; if the queue owns recovery, the watermark must advance *past* the failure. Worse, holding at the last contiguous success means one persistently-failing early message pins the watermark and forces a full re-scan of every later row every poll. Fix: pick one — advance the watermark to the max scanned ROWID and let the **retry queue** be the sole owner of failed URIs; state that explicitly.
- **No settle-window for `attributedBody`: a row read before its blob is populated yields no link, "succeeds" trivially, and the watermark advances past it → the link that lands a moment later is lost.** Section *chat.db reader §2* (line 62) + §5. The C2 fix ("advance only past successful adds") does not help here because a not-yet-written message has *nothing to add*, so the watermark advances legitimately and the message is never revisited. Fix: do not commit the watermark past rows younger than a small settle window (e.g. re-scan a `date`-based lookback), or only advance past rows whose payload (text or blob) was non-empty.
- **`dedup_all_my_playlists` still depends on an undefined ownership check / missing `GET /v1/me` endpoint** (round-1 Must-fix, NOT resolved). Section *Dedup strategy* (line 100) + *Spotify client §4*. `GET /v1/me/playlists` returns followed playlists too; filtering to owned ones needs the current user id from `GET /v1/me`, which is still absent from the §4 client contract and Setup scopes. Fix: add `GET /v1/me` to the client contract and specify `owner.id == me` filtering.

## Medium
- **State-file schema still undefined, now including the newly-added retry queue.** Section *Config §1* (line 46) + §5 (line 78) + *Dedup strategy* (line 102). The plan references `state_path` holding last-seen ROWID + seen-set + durable pending queue but never defines the on-disk shape, nor that the seen-set keys on both track ID and ISRC. Fix: specify the schema — `{watermark ROWID, seen entries [{track_id, isrc}], pending [{uri, source_rowid, attempts}]}` — so restart-safety, ISRC dedup, and retry all stay coherent.
- **`allowed_handles` has no normalization contract → silent sender-filter misses** (round-1 Medium, unresolved). Section *Config §1* (line 45) + reader query `h.id` (line 56). `handle.id` is raw (E.164 phone / email / short code) and one friend spans several handles; naive string match drops valid senders. Fix: define E.164 canonicalization / multi-handle aliasing for the match.
- **Group-chat capture and sender attribution unaddressed** (round-1 Medium, unresolved) — likely the primary use case. Section *chat.db reader §2*. `LEFT JOIN handle ON m.handle_id = h.ROWID` resolves 1:1 DMs only; group `handle_id`/`is_from_me` semantics differ, so `only_from_others`/`allowed_handles` misbehave. Fix: state group-chat scope and how sender is resolved, or declare it a non-goal.

## Low
- **Target-playlist dedup cache goes stale vs. adds from other devices** (carryover). Section *Dedup strategy* source 1 (line 92, "refreshed periodically"). Acceptable at personal scale — note the window explicitly.
- **Architecture diagram still implies Liked Songs is an add target, contradicting §4.** Line 30 ("→ target playlist + Liked Songs, ISRC-aware") vs §4 line 73 (adds to playlist only). Clarify Liked Songs is a dedup *source*, not a write target.

## Impl-note
- Retry-queue poison handling (max attempts / dead-letter for permanently-404 or region-locked URIs) — backoff/attempt tuning, per guidance.
- Exact batch add→persist ordering within a poll.
- `typedstream`/`streamtyped` decode specifics across macOS versions (already under Risks).
- launchd `KeepAlive` momentary two-instance overlap on `state_path`; single-writer guard.
- Cache-refresh / poll interval tuning values.
