# Plan Review R1 — Systems Architect (agent1)

Lens: structural soundness, data model, state/failure transitions, race conditions, missing
endpoint dependencies, cross-section API contract coherence.

## Critical
- **Loop advances `last_seen` ROWID with no failed-add recovery → permanent silent loss of the core deliverable.** Section *Daemon loop (`main.py`)* / *Architecture* ("persist last_seen ROWID"). If a track's `POST /playlists/{id}/tracks` fails (expired token, network, rate limit) but the batch's max ROWID is persisted, that song is never retried and the seen-set does not help (it was never added). Fix: define failure policy in the plan — only advance ROWID past messages whose adds succeeded (or persist a durable pending/retry queue for failed track URIs); an add failure must not commit the ROWID watermark past it.

## Must-fix
- **Read-vs-write race on `attributedBody`: ROWID can advance past a row before its blob is populated → missed messages.** Section *chat.db reader* + *Architecture* poll query. iMessage frequently inserts the `message` row first and writes `attributedBody`/`text` a moment later; a 10s poll can read `text=NULL`+empty blob, extract nothing, then persist ROWID past it. Fix: don't advance the watermark past rows younger than a small settle window (e.g. re-scan a `date`-based lookback), or only commit ROWID for rows whose payload was non-empty.
- **`dedup_all_my_playlists` depends on an undefined ownership check / missing endpoint.** Section *Dedup strategy* ("scan every owned playlist"). `GET /v1/me/playlists` returns followed playlists too, not just owned; owner filtering needs the current user id, which requires `GET /v1/me` — never listed in Components §4 or Setup scopes. Fix: add `GET /v1/me` to the Spotify client contract and specify filtering playlists by `owner.id == me`.

## Medium
- **State persistence schema is undefined though multiple sections depend on its shape.** Section *Config* (`state_path`) + *Dedup strategy* ("persisted local seen-set"). Plan says it holds "last-seen ROWID + seen-set" but never defines format or that the seen-set must key on both track ID *and* ISRC (to match the ISRC dedup rule). Fix: specify the on-disk schema (ROWID watermark + {track_id, isrc} entries) so restart-safety and ISRC dedup stay coherent.
- **`allowed_handles` matching has no handle-normalization contract → silent filter misses.** Section *Config* (`allowed_handles`) + reader query (`h.id`). `handle.id` is raw (E.164 phone, email, or short number) and one friend may appear as several handles; naive string match against config will silently drop valid senders. Fix: define normalization (E.164 canonicalization / multi-handle aliasing) for the match.
- **Group-chat capture and sender attribution unaddressed** — likely the primary use case (friends dropping songs in a group thread). Section *chat.db reader*. `LEFT JOIN handle ON m.handle_id = h.ROWID` resolves 1:1 DMs; group-message sender and `is_from_me` semantics differ, so `only_from_others`/`allowed_handles` may misbehave. Fix: state whether group chats are in scope and how sender is resolved for them (or declare a non-goal).

## Low
- **Target-playlist dedup cache goes stale vs. adds from other devices.** Section *Dedup strategy* source 1. Cache refreshed "periodically"; an add made elsewhere between refreshes can cause a duplicate. Acceptable at personal scale — note the window explicitly.
- **Architecture diagram implies Liked Songs is an add target, contradicting Components.** Section *Architecture* ("→ target playlist + Liked Songs, ISRC-aware") vs §4 which only adds to the playlist. Clarify Liked Songs is a *dedup source*, not a write target.

## Impl-note
- Exact batch-commit ordering (add → persist within a batch) — resolved when wiring M3.
- Spotify `POST /playlists/{id}/tracks` does not dedup server-side; relies wholly on local logic (optionally use `snapshot_id`).
- launchd `KeepAlive` could momentarily overlap two instances writing `state_path`; single-writer guard is an impl detail.
- Cache refresh interval / poll tuning values.
- `typedstream`/`streamtyped` decode specifics across macOS versions (already listed under Risks).
