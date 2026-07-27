# Plan Review R1 — Backend & Privacy Specialist (agent2)

Lens: persistence/consistency, auth/authz, privacy/security of personal contact data.
(Note: no friendship-graph exists in this design — the only "friend" concept is
`allowed_handles`. No graph/bidirectionality/request-lifecycle issues apply; not fabricated.)

## Critical
- **`immutable=1` silently breaks the core poll loop.** Component 2 (`chat.db reader`) opens
  the DB with `file:...?mode=ro`, `immutable=1`. `immutable=1` asserts to SQLite that the file
  is never modified by any process, so it caches pages and will NOT observe rows Messages writes
  after open → new messages are never seen (or stale/corrupt reads). This defeats the entire
  polling premise (silent functionality/data loss). Fix: drop `immutable=1`; use plain
  `mode=ro` and open a fresh read-only connection per poll (chat.db is WAL and actively written).

## Must-fix
- **Initial `last_seen` cursor is undefined → first run dumps entire message history.** Component 1
  (`state_path` / last-seen ROWID) and Milestone M3 ("restart doesn't re-scan old messages") never
  specify the bootstrap value. If it defaults to 0/absent, the first run scans all history and mass-
  adds every Spotify link ever received to the live playlist. Fix: on first run with no persisted
  state, initialize `last_seen = SELECT MAX(ROWID) FROM message` (start from "now"), documented in
  the state model.

## Medium
- **PII (contact handles) written to plaintext logs.** Component 5 ("log every add with track name +
  sender handle") + Component 6 (`StandardOut/ErrorPath` to a log). Handles are phone numbers/emails
  of the user's contacts, stored unencrypted at rest indefinitely. Fix: log a hashed/truncated handle
  by default (or gate full-handle logging behind an explicit config flag) and document log sensitivity.
- **Full Disk Access granted to the shared Python interpreter is over-broad.** Setup step 1 ("Grant
  Full Disk Access to the Python binary / launchd"). Granting FDA to `python3` gives *every* script
  run by that interpreter access to `chat.db` and all protected data. Fix: ship a dedicated venv
  interpreter or app-bundle wrapper and grant FDA to that, not the system/shared python.

## Low
- **Over-broad Spotify scope.** Component 4 requests `playlist-modify-public` though non-goals state a
  single private playlist. Least-privilege: drop it unless a public playlist is actually targeted.
- **Persisted seen-set grows unbounded.** Component 1 (`state_path` seen-set). Fine for MVP but will
  grow forever; note a cap/compaction as a follow-up.

## Impl-note
- WAL read-only access: reading a WAL-mode DB via `mode=ro` when `-shm`/`-wal` exist has known
  access/checkpoint caveats; validate the exact open flags during M1.
- Write/persist ordering: define atomicity between Spotify add, seen-set update, and ROWID advance so
  a crash mid-batch yields at-least-once (dedup-covered), not lost or duplicated adds. Resolve when coding M3.
- Playlist cache staleness (Dedup strategy: "refreshed periodically" + in-memory update) could allow a
  brief double-add window across intervals, esp. with `dedup_all_my_playlists`. Tune refresh during impl.
