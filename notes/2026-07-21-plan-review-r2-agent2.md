# Plan Review R2 — Backend & Privacy Specialist (agent2)

Lens: persistence/consistency, auth/authz, privacy/security of personal contact data.
(As in R1: no friendship graph exists in this design — the only "friend" concept is
`allowed_handles`. No bidirectionality/request-lifecycle/blocking/dedup-graph issues apply.)

## Round-1 fix verification
- **C1 (immutable=1) — RESOLVED.** Component 2 (line 53) now opens a fresh `mode=ro` connection per poll and explicitly forbids `immutable=1`. Correct for a live WAL DB.
- **C2 (watermark vs. failed adds) — RESOLVED, but introduced a new flaw.** Lines 32/77–78 add the success-gated watermark + durable retry queue. See Must-fix below.
- **C3 (first-run flood) — RESOLVED.** Lines 46 & 124–125 seed `last_seen = MAX(ROWID)` on stateless first run.
- **M1 (playlist-read-private) — RESOLVED.** Line 71 adds the scope with correct 403/dedup rationale.

## Critical
- (none new)

## Must-fix
- **Success-gated watermark + retry queue causes permanent head-of-line stall on a poison message.** Component 5 "Watermark discipline" (lines 77–78) + M3 (line 125) freeze the watermark at "the last fully-successful message." A permanently-failing add (deleted/invalid track, 400/403, hard-blocked URI) is never successful, so the watermark never advances past it: every poll re-reads an ever-growing tail (dedup masks re-adds but reprocessing + API calls grow unbounded), and M3's "restart doesn't re-scan old messages" guarantee silently degrades over time. Fix: advance the watermark once each message is **durably accounted for** (added OR enqueued to the retry queue), and make the retry queue an independent durable structure with a bounded max-attempts → dead-letter policy so a poison URI can't stall forward progress.

## Medium
- **Retry queue is not in the state model (cross-section inconsistency).** Component 1 (line 46) says `state_path` holds "last-seen ROWID + seen-set," but Component 5 (line 78) introduces a third durable structure ("pending/retry queue... persisted alongside state") never enumerated. Fix: list the retry queue in Component 1's state model (its schema/location alongside ROWID + seen-set).
- **PII (contact handles) in plaintext logs — UNRESOLVED from R1.** Component 5 (line 79) still logs "sender handle"; Component 6 (line 82) writes to a file indefinitely. Handles are contacts' phone numbers/emails. Fix: hash/truncate handle by default, or gate full-handle logging behind an explicit config flag; document log sensitivity.
- **Full Disk Access granted to the shared Python interpreter is over-broad — UNRESOLVED from R1.** Setup step 1 (line 134) grants FDA to "the Python binary / launchd," exposing `chat.db` + all protected data to every script that interpreter runs. Fix: grant FDA to a dedicated venv interpreter or app-bundle wrapper, not system/shared python.

## Low
- **Over-broad Spotify scope — UNRESOLVED from R1.** Line 71 still requests `playlist-modify-public` though the design targets one private playlist (non-goals, line 146). Least-privilege: drop it unless a public playlist is actually the target.
- **Persisted seen-set grows unbounded.** Component 1 (lines 46/102). Fine for MVP; note a cap/compaction as follow-up.

## Impl-note (do NOT trigger plan fixes)
- Atomicity/ordering across the four persisted steps — Spotify add, seen-set update, retry-queue write, watermark advance — so a crash mid-batch yields at-least-once (dedup-covered), not lost/duplicated. Resolve when coding M3.
- Retry-queue backoff/interval curve and dead-letter threshold (tuning values) — decide while implementing the queue.
- Retry-queue entries need track name + sender handle captured at enqueue time so the "log every add" line still works when a retried add later succeeds.
- `allowed_handles` normalization (E.164 phone vs. email vs. raw `handle.id`) for reliable matching — resolve during M1/M3.
- Playlist-cache staleness ("refreshed periodically" + in-memory update, esp. `dedup_all_my_playlists`) permits a brief double-add window across intervals; tune refresh during impl.
