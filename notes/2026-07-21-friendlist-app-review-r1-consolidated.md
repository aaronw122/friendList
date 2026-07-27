# Friend List — Round-1 Review Consolidated (3 reviewers)

Counts — Critical: 2 · Must-fix: 8 · Medium: 10 · Low: 4 · Impl-note: 12

## Critical

- **[C1] TCC Full Disk Access won't cover the separate agent binary** (agent1) — §Architecture / §Components 2 "Background scanner agent" / §Risks bullet 1. FDA is keyed per-executable by code identity; granting it to `FriendList.app` does not propagate to the nested `friendlist-agent`, so `chat.db` reads get denied and the core function silently never runs. Fix: collapse app+agent into one executable — register the main app as login item (`SMAppService.mainApp`, `LSUIElement`/`MenuBarExtra`) and poll `chat.db` in the app process that holds FDA. Same cdhash = same TCC identity; also removes M1/M2 keychain+state concurrency problems.
- **[C2] Public-distribution model non-viable under Spotify quota policy** (agent2) — §Components 5 / §Distribution / §Risks "Spotify app quota". One embedded shared `client_id` means all installs count against one app; Feb 2026 dev mode caps at 5 users (plan says ~25) and extended quota needs registered business + 250k MAU. Fix: re-architect to bring-your-own `client_id` — each user creates their own Spotify dev app and pastes `client_id` in onboarding (each is own owner, dev mode, no allowlist). Drop "one Spotify developer app backs all installs."

## Must-fix

- **[M1] Two concurrent writers to shared state container** (agent1) — §Components 8 StateStore + §Components 9 Settings. Agent writes runtime state, app writes settings to same container; single-writer guard only stops duplicate agent launches. Fix: split agent-owned runtime state from app-owned settings into separate files, or one SQLite/WAL DB with a defined single writer + file coordination; write the ownership contract explicitly. (Moot under C1 single-executable.)
- **[M2] Spotify refresh-token rotation: ownership + persistence** (agent1 + agent2, overlap — strong signal) — §Components 5 "silent access-token refresh". PKCE refresh returns a new `refresh_token`; if reused or refreshed by both app+agent, auth silently dies. Fix: designate one refresh owner, serialize refresh under keychain/file lock, and atomically overwrite the stored `refresh_token` with the rotated value every refresh.
- **[M3] Watermark advancement ambiguous, can silently drop adds** (agent1) — §Daemon loop & watermark discipline. "Advance ROWID past every terminally-resolved message" reads as non-contiguous, skipping a failed-before-enqueue message forever. Fix: define watermark = highest ROWID such that all lower ROWIDs are terminally resolved (stop at first unresolved); never advance past a hole.
- **[M4] Dev-mode allowlist requires each user's email, contradicts privacy pillar** (agent2) — §Product shape pillar 1 / §Privacy / §Onboarding 3. Shared-client_id design forces users to send email for allow-listing. Fix: BYO-client_id (C2) removes this — state explicitly that no shared allowlist exists.
- **[M5] Denied / never-granted FDA has no path** (agent3) — §Onboarding 2 / §Components 1. Onboarding only "polls for access"; a denial hangs screen 2 with no error/skip/retry. Fix: define an explicit "not granted / try again / can't continue" state and a graceful stuck-screen (agent installed but paused).
- **[M6] Revoked Spotify token has no user-facing recovery** (agent3) — §Product shape (three pillars) / §Components 2. Headless agent stops adding on revoked/expired refresh token with no notification channel, breaking "never needs to be opened again." Fix: define a menubar attention/error state ("Reconnect Spotify") and how the headless agent signals the UI to prompt re-auth.
- **[M7] Privacy section contradicts what is persisted** (agent3) — §Privacy (explicit) vs §Components 8 State store. Privacy claims only Spotify track IDs persist, but retry queue persists source chat + sender and SourceFilter persists `allowed_chats`/`allowed_handles`. Fix: reconcile — qualify the privacy claim to admit chat/sender identifiers are stored locally, or drop those fields from persisted state.
- **[M8] FDA grant forces app relaunch mid-onboarding; resume unspecified** (agent3) — §Components 1 / §Onboarding 2. macOS commonly restarts the app on FDA grant, but `didOnboard` is only set at the end, so post-grant relaunch behavior is undefined. Fix: persist onboarding-step so a post-grant relaunch resumes at the scope screen.

## Medium

- **[Med1]** Link regex misses internationalized `open.spotify.com/intl-xx/track/ID` paths (agent1, §Components 4) — allow optional `/intl-[a-z]+` locale segment.
- **[Med2]** Keychain access-group sharing prerequisites unstated (agent1, §Components 5 / §Tech stack) — needs data-protection keychain + `keychain-access-groups` entitlement in both targets, same Team ID. (Moot under C1.)
- **[Med3]** `chat_message_join` LEFT JOIN can emit multiple rows per message (agent1, §Components 3 SQL) — GROUP BY `m.ROWID`/DISTINCT or deterministically pick one chat.
- **[Med4]** Liked Songs dedup cannot be ISRC-aware as specified (agent2, §Dedup) — `contains?ids=` keys on track ID only; note ID-only or make full-library ISRC scan opt-in.
- **[Med5]** Developer/user Premium requirement (agent2, §Tech stack / §Risks) — under BYO-client_id each user is an owner and needs Premium; call out as adoption constraint before M2/M5.
- **[Med6]** Cancelled/failed Spotify auth has no described state (agent3, §Onboarding 3) — define retry/cancel copy; Done unreachable until auth succeeds.
- **[Med7]** Deleted "Friend List" playlist has no recovery (agent3, §Dedup / §Components 5) — on 404, recreate playlist (or menubar prompt) and re-persist ID.
- **[Med8]** `SMAppService` registration may require Login Items approval, not surfaced (agent3 Medium + agent1 Low, overlap) — §Onboarding 4 "Done" / §Components 2. Check `service.status` post-register; add detection/explainer to enable in Login Items if `.requiresApproval`.
- **[Med9]** Picker-reveal vs FDA-request ordering ambiguous (agent3, §Onboarding 2) — gate the conversation picker on the probe read succeeding so it isn't empty.
- **[Med10]** Screen-2 grant copy overclaims vs persistence (agent3, §Onboarding 2) — "stored" is misleading given local seen-set + retry queue; reword to "never leaves this Mac."

## Low

- **[L1]** Confirm `friendlist://auth-callback` registered as Redirect URI in Spotify dashboard (agent2, §Components 5); custom schemes still supported post-27-Nov-2025 migration.
- **[L2]** Welcome hero shows "Spotify mark" but branding is a Messages+Spotify fusion mark (agent3, §Onboarding 1 vs §Branding) — use fusion mark.
- **[L3]** Scope question says "group chats" but picker also lists DMs (agent3, §Onboarding 2) — reword to "any chats — or only certain ones?"
- **[L4]** FDA access-polling has no timeout/skip (agent3, §Components 1) — after N seconds show a "still waiting / open Settings again" nudge.

## Impl-notes

- **chat.db / SQLite (agent1):**
  - Read-only WAL open may return `SQLITE_READONLY_CANTLOCK`; verify per-poll fresh read-only connections see new rows (M1).
  - `NSUnarchiver` deprecated in Swift for typedstream `attributedBody`; use `NSAttributedString(data:documentAttributes:)` (streamtyped) or a typedstream parser with byte-scan fallback.
  - Advisory `flock` for duplicate-launch protection is fine; keep lock in Application Support.
  - First-run `MAX(ROWID)` seeding: pick a single seeder (agent) to avoid double-seed.
- **Spotify API / OAuth (agent2):**
  - `GET /v1/playlists/{id}/tracks` pages at 100 — paginate dedup cache build.
  - Per-track `GET /v1/tracks/{id}` (ISRC) + `contains` can hit the 30s rolling rate limit; batch `?ids=` (up to 50).
  - Include and verify OAuth `state` param for CSRF on the ASWebAuthenticationSession round-trip.
  - `ASWebAuthenticationSession(callbackURLScheme:)` takes the bare scheme `friendlist`, not the full URL.
- **Distribution / signing (agent2):** Notarize the bundled agent binary too — Hardened Runtime + secure timestamp; both binaries need matching `keychain-access-groups` (same Team ID) for the shared Keychain item. (Moot if C1 collapses to one executable.)
- **Copy / UX (agent3):**
  - Casing inconsistency "friend list" (Welcome) vs "Friend List" (app/playlist) — pick one.
  - Verify exact `x-apple.systempreferences:` FDA deep-link target per macOS version at build time.
  - Tune FDA-detection poll interval / probe cadence during implementation.
