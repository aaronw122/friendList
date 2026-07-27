# Friend List — Review: macOS/Swift Systems Architect (r1-agent1)

Persona lens: app+agent split, SMAppService lifecycle, chat.db read-only WAL, attributedBody, Keychain access groups, state persistence, watermark discipline, TCC FDA coverage of the bundled agent.

## Critical

- **TCC Full Disk Access will not cover the separate agent binary.** (§Architecture; §Components 2 "Background scanner agent"; §Risks bullet 1) FDA (`kTCCServiceSystemPolicyAllFiles`) is keyed per-executable by code identity. A launchd-launched LaunchAgent is its own responsible process; granting FDA to `FriendList.app` does **not** propagate to the nested `friendlist-agent` binary, and dragging a hidden `Contents/Library` executable into System Settings is unworkable UX — so the agent's `chat.db` reads get denied and the core function silently never runs. This isn't a "validate later" risk; the architecture is committed to a design that will fail at M5. **Fix:** collapse app+agent into one executable — register the main app itself as a login item (`SMAppService.mainApp`, `LSUIElement`/`MenuBarExtra`, launch-at-login) and do the `chat.db` polling in the app process that already holds the FDA grant. Same cdhash = same TCC identity, and it also eliminates the Keychain-sharing and state-concurrency problems below.

## Must-fix

- **Two concurrent writers to the shared state container.** (§Components 8 StateStore + §Components 9 Settings) The agent writes `last_seen`/seen-set/retry queue; the app writes settings (pause, playlist rename, chat scope) to the *same* container. The stated "single-writer" guard (§Components 2) only prevents duplicate *agent* launches — it does nothing for app↔agent races → lost updates / JSON corruption. **Fix:** split agent-owned runtime state from app-owned settings into separate files, or use one SQLite DB (WAL) with a defined single writer + file coordination; write the ownership contract explicitly.
- **Spotify token-refresh ownership unspecified.** (§Components 5 "silent access-token refresh") PKCE refresh rotates the refresh token; if both app and agent refresh independently, each invalidates the other's stored refresh token → agent stops adding. **Fix:** designate one refresh owner (the agent), have the app only consume the shared token, serialize refresh under a keychain/file lock, and persist the rotated `refresh_token` atomically.
- **Watermark advancement is ambiguous and can silently drop adds.** (§Daemon loop & watermark discipline) "advance ROWID past every terminally-resolved message" reads as per-message (non-contiguous) advancement — which would skip a failed-before-enqueue message forever, contradicting the plan's own no-loss guarantee. **Fix:** define watermark = highest ROWID such that *all* lower ROWIDs are terminally resolved (stop at the first unresolved); never advance past a hole.

## Medium

- **Link regex misses internationalized paths.** (§Components 4) `https?://open\.spotify\.com/track/…` silently drops the now-common `open.spotify.com/intl-xx/track/ID` form → valid links ignored. **Fix:** allow an optional `/intl-[a-z]+` (or generic locale) path segment before `/track/`.
- **Keychain access-group sharing prerequisites unstated.** (§Components 5; §Tech stack) Cross-executable sharing requires the data-protection keychain (`kSecUseDataProtectionKeychain`) + `keychain-access-groups` entitlement declared in *both* targets under the same Team ID; classic login-keychain ACL sharing behaves differently. **Fix:** specify the entitlement + data-protection-keychain contract. (Moot if Critical is adopted — one executable.)
- **`chat_message_join` LEFT JOIN can emit multiple rows per message.** (§Components 3 SQL) A message in >1 chat yields duplicate rows → duplicate filter/parse passes. **Fix:** resolve each message once (GROUP BY `m.ROWID` / DISTINCT, or deterministically pick one chat).

## Low

- **SMAppService approval state not handled.** (§Onboarding 4 "Done"; §Components 2) Registration can land in `.requiresApproval` (Login Items toggle); onboarding assumes success. **Fix:** check `service.status` post-register and guide the user to enable it if pending.

## Impl-note

- Read-only WAL open may return `SQLITE_READONLY_CANTLOCK` when no writer holds the db / `-shm` can't be created; verify per-poll fresh read-only connections see new rows (already scheduled M1). (§Components 3)
- `NSUnarchiver` is deprecated/unavailable in Swift for typedstream `attributedBody`; use `NSAttributedString(data:documentAttributes:)` (streamtyped) or a typedstream parser with the byte-scan fallback. (§Components 3)
- Advisory `flock` for duplicate-launch protection is fine; keep the lock in Application Support. (§Components 2)
- First-run `MAX(ROWID)` seeding: pick a single seeder (agent) to avoid app/agent double-seed; the onboarding→first-launch gap is acceptably skipped. (§Components 8)
