# R2 Plan Review — Consolidated Summary

**Round-1 fix verdicts (unanimous):** C1 (drop `immutable=1` / `mode=ro`) applied, C2 (success-gated watermark) applied but **regressed** (see M1), C3 (seed `MAX(ROWID)`) fixed, M1-r1 (`playlist-read-private`) fixed.

**Tier counts (deduped):** Critical 1 · Must-fix 5 · Medium 8 · Low 5 · Impl-notes ~10

## Critical
- [C1] `mode=ro` alone can't read a live WAL DB → daemon misses newest rows still in `-wal` (the exact rows it exists to catch). chat.db reader §2 line 53. Fix: open read-write but SELECT-only, or snapshot-copy chat.db+-wal+-shm to temp and read the copy; drop `mode=ro` as sole guarantee. NEW — introduced by the C1 fix. Contested tier: agent1=Critical; agent2/agent3=impl-note.

## Must-fix
- [M1] Watermark-hold and retry-queue are two conflicting recovery mechanisms → poison message stalls watermark forever + unbounded tail re-scan. §5 lines 77–78 + M3 line 125 + Arch §32. All 3 reviewers. Fix: advance watermark past every terminally-resolved row (no link/filtered/dedup-skip/added/enqueued); make durable retry queue sole owner of failures with bounded max-attempts → dead-letter. NEW — C2 regression.
- [M2] No settle-window for attributedBody: row read before blob populated yields no link, 'succeeds' trivially, watermark advances, later-landing link lost. §2 line 62 + §5. Fix: don't commit watermark past rows younger than a settle window, or only advance past non-empty payloads. Pre-existing, unmasked by C2.
- [M3] dedup_all_my_playlists depends on undefined ownership check / missing GET /v1/me. Dedup strategy line 100 + §4. Fix: add GET /v1/me to client contract, filter owner.id==me. Pre-existing — R1 unresolved.
- [M4] OAuth callback receiver undefined. §4 + Setup step 2 line 135. PKCE needs loopback HTTP listener for auth code. Fix: add local callback-server responsibility to spotify.py. Pre-existing — R1 unresolved.
- [M5] Config missing client_id and redirect_uri/callback_port. §1 line 46 vs Setup steps 2–3. Fix: add them to §1 Config. Pre-existing — R1 unresolved.

## Medium
- State-file schema undefined / retry queue not in state model (agent1+agent2). Specify {watermark ROWID, seen [{track_id,isrc}], pending [{uri,source_rowid,attempts}]}.
- allowed_handles has no normalization contract (raw E.164/email/short-code; one friend many handles). Define canonicalization/aliasing.
- Group-chat capture & sender attribution unaddressed (LEFT JOIN handle resolves DMs only). State scope or non-goal.
- PII contact handles in plaintext logs (§5 line 79 + §6 line 82). Hash/truncate or gate behind flag. Pre-existing R1.
- Full Disk Access to shared Python interpreter over-broad (Setup step 1 line 134). Grant to dedicated venv wrapper. Pre-existing R1.
- only_from_others=true default conflicts with M3 acceptance test (self-texts filtered). Use 2nd handle or flip default for M1/M3. Pre-existing R1.
- dedup_liked_songs=true default may drop wanted songs absent from friend playlist (§1 line 48). Reconsider or scope to playlist-only. Pre-existing R1.
- No defined behavior when auth fails unattended (revoked/expired token → silent stop). Define re-auth/notify path. Pre-existing R1.

## Low
- Target-playlist dedup cache stale vs other-device adds — note window (line 92).
- Architecture diagram implies Liked Songs is an add target, contradicts §4 (line 30 vs 73) — clarify it's dedup source.
- Over-broad playlist-modify-public scope for single private playlist (line 71) — drop. Pre-existing R1.
- Persisted seen-set grows unbounded (§1 46/102) — note cap/compaction.
- No user-facing success/failure feedback, log-only (§5 line 79) — add macOS notification or accept for MVP. Pre-existing R1.

## Impl-notes
- Retry-queue poison handling: max-attempts/dead-letter, backoff curve (tuning).
- Atomicity/ordering across 4 persisted steps → at-least-once on crash; batch add→persist ordering.
- Retry-queue entries need track name + sender handle at enqueue for 'log every add' on retry success.
- allowed_handles E.164/email/multi-handle normalization — during M1/M3.
- Playlist-cache staleness / refresh cadence — tuning.
- mode=ro WAL visibility verify during M1 (agent1 elevated to C1).
- typedstream/streamtyped decode across macOS versions (Risks).
- Regex ?si= share-token stripping & spotify:track: URI edge cases (§3).
- launchd KeepAlive two-instance overlap on state_path — single-writer guard.

## Cross-reviewer agreement
- M1 (watermark/retry conflict): all 3 — strongest signal, NEW regression from C2.
- State-file schema/retry-queue-in-state-model: agent1 + agent2.
- mode=ro WAL visibility: all 3 flag it, but tiered differently (agent1 Critical, others impl-note).