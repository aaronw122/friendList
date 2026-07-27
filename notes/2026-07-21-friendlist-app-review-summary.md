# Plan Review Summary (Friend List macOS app)

**Plan / Rounds: 3 / Final revision: none**

Plan: `/Users/aaron/code/personal/Projects/friendList/PLAN.md` — a native macOS SwiftUI menubar app that watches Messages (`chat.db`) for friend-sent Spotify links and auto-adds them to a playlist, privately and set-and-forget. Reviewed over 3 rounds, each with 3 opus reviewers → consolidation → opus Devil's Advocate → clear-fable Judge. `PLAN.md` carries no `revision:` frontmatter.

Final judge verdict (R3): **architecture SOUND after 3 rounds.** The single-executable / in-process-scanner / BYO-client_id / watermark-dedup design has failed to dent across three rounds. No further review round warranted; remaining risk is empirical (attributedBody decoding, dev-mode write gate) and belongs to milestones, not reviews.

## Issues Found & Fixed

### Round 1 — feasibility prerequisites (2 Critical, 2 Must-fix upheld)
- **C1 (Critical) — FDA per-executable.** TCC Full Disk Access is keyed per-executable code identity; granting it to `FriendList.app` would not cover the nested `friendlist-agent` binary, so `chat.db` reads fail silently and the "seeing" leg never runs. **Fix:** collapse app + agent into ONE executable — register the main app as login item (`SMAppService.mainApp`, `LSUIElement`/`MenuBarExtra`) and poll `chat.db` in the app process that holds FDA (same cdhash = same TCC identity). Also moots M1 and the keychain-sharing half of M2.
- **C2 (Critical) — shared client_id non-viable under Spotify quota.** One embedded shared `client_id` counts all installs against one dev-mode app (Feb 2026 cap = 5 users; extended quota needs a registered business at 250k MAU) — incompatible with public web download. **Fix:** bring-your-own `client_id` — each user creates their own Spotify dev app and pastes `client_id` in onboarding (each is own owner, dev mode, no allowlist).
- **M2 (Must-fix) — PKCE refresh-token single-use rotation.** Spotify PKCE refresh tokens are single-use and rotate every refresh; two readers or a non-atomic write silently kills auth forever. **Fix:** single designated refresh owner + serialized refresh under lock + atomic Keychain overwrite of the rotated token on every refresh. (C1's single-executable does not moot this — the persistence requirement bites even a lone writer.)
- **M6 (Must-fix) — no auth-failure surface.** A revoked/expired token stops adds with no notification, and M2 makes that likely. **Fix:** menubar attention/error state ("Reconnect Spotify") plus a headless-scanner → UI signaling path. Judge escalated M2+M6 as one work item (silent auth death + no surface = permanent invisible product death).

R1 **dismissed:** M3 (watermark misread — advancement is already contiguous), M4 (email allowlist — subsumed by C2). **Downgraded:** M1→Med, M5→Low, M7→Low, M8→Med.

### Round 2 — launch-survivability cluster (2 Must-fix upheld)
All three reviewers confirmed R1 fixes (C1/C2/M2/M6) genuinely resolved. New issues were side-effects of the C1 menubar-only collapse. Judge's framing: R2 exposes **whether the app reliably keeps existing across quits, crashes, and logins** — the seam R1 never stress-tested.
- **M3 (Must-fix) — app translocation.** A quarantined app launched from DMG/Downloads runs from a randomized read-only path; the login item registers against a path that evaporates at next login → silent permanent death on a very common user path. **Fix:** detect translocated / not-in-`/Applications` and require move to `/Applications` **before** requesting FDA or registering the login item.
- **M4 (Must-fix) — login-item approval.** `SMAppService` registration can land `.requiresApproval` or be toggled off; the "never open again" promise then fails silently. **Fix:** check `SMAppService.status` on every launch, surface "Enable Friend List in Login Items" (via `openSystemSettingsLoginItems()`) through the M6 attention surface.

Folded into the launch-survivability work item: **M1** (crash recovery — `SMAppService.agent` KeepAlive watchdog pointing at the same bundled executable, or document login-only recovery in writing), **M8** (persist onboarding step + re-present/activate the onboarding window after an FDA-grant relaunch), **M7** (disclose Premium/BYO requirement on Welcome, before the FDA grant), and the **Spotify write-verification gate** at M2 (first action of M2 = a live `POST /v1/playlists/{id}/tracks` from a fresh dev-mode app).

R2 **dismissed:** M2 (owner self-add — a dev-app owner needs no Users-and-Access self-add; owner==user). **Downgraded:** C1→Med (folds into R1-M8; FDA grant does not actually kill a running app), M1→Med, M5→Low (=R1), M6→Low (=R1), M7→Med.

### Round 3 — regressions from the R2 SMAppService.agent mechanism (1 Critical, 1 Must-fix upheld)
R2 blessed the `SMAppService.agent` + KeepAlive mechanism but left plist semantics and the process-lifecycle contract unspecified; the plan wired both wrong.
- **C1 (Critical) — duplicate live instance.** `SMAppService.agent().register()` with `Program`=own executable + `RunAtLoad` starts a launchd instance B while the LaunchServices onboarding instance A is still alive (any later Finder-open starts yet another). `flock` blocks double-*writes*, not two UIs, and this duplicate races the single-use refresh-token serialization and single-writer state invariants the R1/R2 design now load-bears on. **Fix:** single-instance contract — after `register()` the onboarding instance calls `NSApp.terminate` so launchd is sole owner; on any launch, bundle-id `NSRunningApplication` check → activate-existing-and-exit; `flock` loser exits 0 cleanly.
- **MF1 (Must-fix) — boolean KeepAlive respawns after clean Quit.** `KeepAlive=true` restarts on *any* exit, so a deliberate menubar Quit respawns (~10s throttle) — "I quit it and it kept reading my messages" breaks the trust pitch. **Fix:** `KeepAlive={SuccessfulExit=false}` (crash-restart only, RunAtLoad login-start preserved); route Quit through `SMAppService.unregister()`/bootout; pause/resume stays an in-process flag. C1 + MF1 must land together (with boolean KeepAlive, a flock-loser "just exits" becomes a respawn loop).

R3 **dismissed:** MF2 (Spotify owner self-add — settled, same false premise as R2-M2; owner==user needs no allowlist). **Downgraded:** MF3 (privacy retry-queue wording) → Low (third filing, unchanged from R1-M7/R2-M6).

## Remaining (not fixed)

Low / Medium items noted but not blocking, carried across rounds:
- **MF3 / privacy wording (Low)** — §Privacy "Local only … beyond what filtering needs" tensions with the retry queue persisting source chat + sender. Preferred cheap fix: store only track URI + attempt count in retry entries (better privacy posture too), or amend the §Privacy sentence. Never leaves the Mac, so the privacy pillar is intact.
- **Editing client_id re-auth (Medium)** — changing `client_id` in Settings silently invalidates stored tokens; must clear Keychain tokens + playlist ID and drive "Reconnect Spotify."
- **Liked Songs ISRC-only (Medium)** — dedup is track-ID-only, contradicting the "ISRC-aware" claim; state ID-only or make full-library ISRC scan opt-in.
- **Denied-FDA dead-end (Medium)** — never-granted/denied FDA still dead-ends (compounded by M8 resume assuming "FDA in hand"); add an explicit not-granted state with retry + graceful installed-but-paused exit.
- **OAuth cancel/mismatch state (Medium)** — cancelled/failed onboarding OAuth (incl. BYO redirect_uri mismatch, mistyped client_id) has no state; "Done" unreachable until auth succeeds — define cancel/retry copy and targeted validation error.
- **Assorted Low:** `playlist-modify-public` scope unnecessary (playlist is private) — drop it; translocation guard placement (run pre-Welcome, not mid-flow); Premium now a hard requirement (firm up Welcome copy); playlist-gone (404) recovery — recreate + re-persist ID; internationalized `open.spotify.com/intl-xx/track/ID` regex; FDA poll timeout/skip nudge; Messages+Spotify fusion mark on Welcome hero; scope-question DM wording; "never leaves your Mac" footer copy.

**Dismissed (not defects):** MF2 / R2-M2 Spotify owner self-add (owner==user needs no allowlist — settled twice); R1-M3 watermark (advancement already contiguous by construction); watermark/email allowlist and other shared-client_id artifacts (mooted by C2 BYO pivot); R1 watermark-drop and self-add claims.

## Implementation Notes

Carried across rounds as milestone-level empirical verification, not review items:
- **attributedBody decoding** — `NSUnarchiver` deprecated/unavailable in Swift for typedstream blobs; use `NSAttributedString(data:documentAttributes:)` (streamtyped) or a typedstream parser with a `https://…spotify` byte-scan fallback.
- **`chat_message_join` duplicate rows** — LEFT JOIN emits multiple rows for a message in >1 chat; `GROUP BY m.ROWID`/`DISTINCT` or pick one chat deterministically.
- **WAL `SQLITE_READONLY_CANTLOCK`** — read-only WAL open may fail when `-shm` can't be created; confirm fresh per-poll read-only connections see just-arrived rows.
- **OAuth `state` / CSRF** — generate + verify a `state` param on the ASWebAuthenticationSession round-trip.
- **callbackURLScheme** — `ASWebAuthenticationSession(callbackURLScheme:)` takes the bare scheme `friendlist`; dashboard/Info.plist register `friendlist://auth-callback` — keep all three consistent. LSUIElement windowless process must materialize a window + `presentationContextProvider` before re-auth.
- **LaunchAgent plist** — reference the executable path (`Contents/MacOS/FriendList`), not the `.app`; live in `Contents/Library/LaunchAgents/`; `Label` = `plistName` passed to `SMAppService.agent(plistName:)`; prefer bundle-relative so it resolves after the `/Applications` move; re-validate/re-register on each run (stale absolute `Program` → silent no-launch). After a Sparkle in-place update, re-register the agent so launchd runs the new binary; confirm the Developer ID designated requirement stays stable so the FDA/TCC grant survives version bumps.
- **Notarization entitlements** — enumerate Hardened Runtime + secure timestamp (network client, Keychain, app-sandbox-off for FDA); ensure the bundled `Contents/Library/LaunchAgents/*.plist` sits inside the signed bundle.
- **Dev-mode tester cap** — now 5 users (was 25 in R2 copy); update any plan copy stating a number. Dev-app owner account must equal the Premium/auth account.
- **Casing** — "friend list" (Welcome) vs "Friend List" (app/playlist) — pick one.

## Reviewer Personas

Three opus reviewers per round, each round adjudicated by an opus Devil's Advocate and a clear-fable (claude-fable-5, web disabled) Judge:
1. **macOS / Swift Systems Architect** — TCC/FDA, SMAppService lifecycle, launchd plist semantics, SQLite/WAL, process invariants.
2. **Spotify OAuth / API + Distribution Specialist** — PKCE token rotation, dev-mode quota, notarization/signing, redirect URIs.
3. **Product / Privacy / Onboarding UX Reviewer** — privacy pillar, onboarding flow, attention-state surfaces, copy.
