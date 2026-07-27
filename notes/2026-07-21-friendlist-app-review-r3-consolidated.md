# Friend List — Review R3 Consolidated

Sources: r3-agent1 (macOS/Swift systems), r3-agent2 (Spotify OAuth/API + distribution), r3-agent3 (Product/Privacy/Onboarding UX).
All three verified R2 fixes M1/M3/M4/M7/M8 + Spotify write-gate as resolved; M1 (`SMAppService.agent`, `Program`=own executable) is where the new defects were introduced.

**Counts:** Critical 1 · Must-fix 3 · Medium 5 · Low 5 · Impl-notes 11

## Critical
- [C1] `SMAppService.agent().register()` with `Program`=own executable spawns a duplicate live instance and there is no single-instance/handoff design — §Onboarding 4 / §Architecture (lines 76-78) / §Components 1–2 / §Tech stack — at Done, `RunAtLoad` starts a launchd instance B while the LaunchServices onboarding instance A is still alive (and any later Finder-open of the .app starts yet another); `flock` only blocks double-*writes*, not two UIs, and the plan never says which instance wins. **Fix:** define the single-instance contract — after `register()` the onboarding instance calls `NSApp.terminate` so the launchd instance is sole owner; on any launch, bundle-id `NSRunningApplication` check → activate-existing-and-exit; lock-loser exits 0 cleanly. — **(NEW — introduced by M1 fix; all 3 agents, agent1=Critical, agent2/agent3=Must-fix)**

## Must-fix
- [MF1] `KeepAlive=true` (boolean) defeats the menubar "Quit" and turns clean exits into a ~10s respawn storm — §Architecture (line 77) / §Components 1 (line 79) & 2 (line 111) / §Tech stack (line 212) / §Onboarding 4. **Fix:** set `KeepAlive={SuccessfulExit=false}` (crash-restart only) so RunAtLoad still gives login-start + crash-restart while a clean Quit stays quit; route "Quit" through `SMAppService.unregister()`/bootout; keep pause/resume as an in-process flag; add to M4 acceptance. — **(NEW — introduced by M1 fix; all 3 agents)**
- [MF2] Onboarding + M2 omit the mandatory Spotify "Users and Access" allowlist step; owner's own account must be added or auth returns "user not registered" — §Onboarding 3 / §Components 5 (line 141) / §M2; plan now incorrectly says "no allowlist" (dev-mode cap is 5 users). **Fix:** add onboarding sub-step "add your own Spotify account under Users and Access" with exact dashboard path; make M2/M3 acceptance require auth as a freshly-allowlisted account. — **(carried-over; agent1)**
- [MF3] Privacy "Local only" claim contradicts Component 8's persisted retry queue, which stores source chat + sender per entry — §Privacy vs §Components 8 (a re-POST needs only the track URI). **Fix:** drop chat/sender from retry entries (store track URI + attempt count only), or amend the privacy line to admit chat/sender are persisted locally for retry. — **(carried-over; agent3)**

## Medium
- [M1] Re-opening FriendList.app after launchd-exec silently does nothing (can't reach Settings) — §Components 2 line 113 — **(NEW; agent1; overlaps C1 — second-launch UX facet, fix via same activate-existing handshake).**
- [M2] Editing client_id in Settings silently invalidates stored tokens with no forced re-auth — §Components 9 vs §Components 5; changing client_id must clear Keychain tokens + playlist ID and drive "Reconnect Spotify" — **(carried-over; agent2).**
- [M3] Liked Songs dedup is track-ID-only, contradicting the "ISRC-aware" claim — §Dedup strategy source 2; state it's ID-only or make full-library ISRC scan opt-in — **(carried-over; agent2).**
- [M4] Denied/never-granted FDA still dead-ends, now compounded by M8 resume (assumes "FDA in hand") — §Onboarding 2 / §Component 1; add explicit not-granted state with retry + graceful installed-but-paused exit — **(carried-over, compounded by M8=NEW; agent3).**
- [M5] Cancelled/failed onboarding OAuth (incl. BYO redirect_uri mismatch) has no state — §Onboarding 3; define cancel/retry copy, "Done" unreachable until auth succeeds — **(carried-over; agent3).**

## Low
- [L1] Premium is now a HARD requirement — change Welcome's "may be required" to firm "requires Spotify Premium" (§Onboarding 1 line 45; invalidates R2's drop-Premium suggestion) — **(NEW policy; agent1).**
- [L2] `playlist-modify-public` scope is unnecessary (playlist is private) — drop it (§Components 5) — **(carried-over; agent2).**
- [L3] BYO Connect step has no validation for mistyped client_id / mismatched redirect URI — validate the round-trip with a targeted error (§Onboarding 3 / §Components 5) — **(carried-over; agent2; relates to M5).**
- [L4] Translocation guard sits mid-flow (start of screen 2), so user sees Welcome → move+relaunch → Welcome again — run guard pre-Welcome on launch (§Onboarding 2) — **(NEW placement, from M3 fix; agent3).**
- [L5] Playlist-gone recovery unspecified — on 404 recreate the playlist + re-persist ID via a dedicated attention action (§Component 1) — **(carried-over; agent3).**

## Impl-notes
- **LaunchAgent plist:** reference executable path (`Contents/MacOS/FriendList`), not the `.app`; live in `Contents/Library/LaunchAgents/`; `Label` = `plistName` passed to `SMAppService.agent(plistName:)`; prefer bundle-relative so it resolves after the /Applications move; a stale absolute `Program` path after user move/rename → silent no-launch, so re-validate/re-register on each run (agent1+agent3).
- **TCC/FDA attribution:** confirm bundle identity resolves when launchd starts `Contents/MacOS/…` directly — already gated at M4 (agent1+agent3).
- **Sparkle update ↔ SMAppService.agent:** after in-place update, re-register the agent so launchd runs the new binary; confirm Developer ID designated requirement stays stable so FDA/TCC grant survives version bumps (agent2).
- **Notarization entitlements:** enumerate Hardened Runtime + secure timestamp (network client, Keychain, app-sandbox-off for FDA); ensure bundled `Contents/Library/LaunchAgents/*.plist` is inside the signed bundle (agent2).
- **OAuth callbackURLScheme consistency:** `ASWebAuthenticationSession(callbackURLScheme:)` takes bare `friendlist`; dashboard/Info.plist register `friendlist://auth-callback` — keep all three consistent (agent2+agent3).
- **Re-auth presentation anchor:** the launchd-started LSUIElement windowless process must materialize a window + `presentationContextProvider` before `ASWebAuthenticationSession` (agent2).
- **OAuth `state` (CSRF):** generate + verify a `state` param on the round-trip (agent2).
- **attributedBody:** `NSUnarchiver` deprecated/unavailable in Swift — use `NSAttributedString(data:documentAttributes:)` (streamtyped) or a typedstream parser with the `https://…spotify` byte-scan fallback (agent1).
- **Dev-mode test-user cap is now 5** (was 25 in R2) — update any plan copy that states a number (agent1).
- **BYO account identity:** dev-app owner account must equal the Premium/auth account; surface the exact `friendlist://auth-callback` redirect-URI mismatch hint on auth failure (agent3).
- **Casing:** "friend list" (Welcome) vs "Friend List" (playlist/app) — pick one (agent3).
