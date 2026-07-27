# Friend List Plan Review R3 — Spotify OAuth/API + Distribution Specialist (r3-agent2)

Persona lens: ASWebAuthenticationSession PKCE + `friendlist://auth-callback`, BYO client_id, token storage/refresh, playlist bootstrap/add/dedup + scopes, ISRC, and macOS distribution (Developer ID / notarization / stapling / Gatekeeper / Spotify dev-quota).

## Round-2 fix verification
- **M3 (translocation / not-in-/Applications guard first) — RESOLVED.** Onboarding 2 makes the move-to-/Applications check the very first gate before FDA; Component 1 (M3) + Distribution align. Registration now binds to the final `/Applications` path; LetsMove relaunch via LaunchServices yields one instance. Clean.
- **M4 (SMAppService.status check) — RESOLVED.** Onboarding 4 + Component 1 (M4): non-`.enabled` raises the "Enable in Login Items" attention item on the M6 machinery, deep-linked. Good.
- **M8 (persist onboarding marker, re-present after FDA relaunch) — RESOLVED.** Onboarding 2 + Component 1: `didOnboard`-false re-present resumes from a persisted step marker in Application Support (path-independent, survives the /Applications move). Good.
- **M7 (disclose Spotify account + BYO dev-app + Premium on Welcome) — RESOLVED.** Onboarding 1 heads-up line states account, one-time dev-app creation, and possible Premium *before* FDA. Good.
- **Spotify write-gate (M2) — RESOLVED.** M2's first, gating action is a live `POST /v1/playlists/{id}/tracks` from a fresh Development-Mode app; correctly de-risks the 2025-26 dev-mode-write concern before anything is built on it.
- **M1 (SMAppService.agent, Program = own executable) — PARTIALLY RESOLVED.** FDA-coverage claim is **sound**: TCC keys on bundle id + Developer ID designated requirement / cdhash, so the *same* signed bundle launched by launchd shares the one grant (no second binary to authorize) — the "one code identity, one grant" statement is correct, and RunAtLoad+KeepAlive→login-start+crash-restart is the right launchd mapping. BUT re-launching the *main* .app executable directly via launchd introduces two new lifecycle defects (see Must-fix) that the fix did not reconcile.

## Critical
- (none)

## Must-fix
- **launchd-vs-LaunchServices duplicate instances — the "Program = own executable" agent bypasses LaunchServices, so nothing coalesces two live copies.** §Architecture / §Components 1–2 / §Tech stack / §Milestones M4. Two concrete triggers: (a) at *Done*, registering an agent with `RunAtLoad=true` loads-and-starts it immediately, so a launchd instance spawns while the LaunchServices onboarding instance is still alive; (b) a launchd-`Program`-started process isn't LaunchServices-registered, so a later Finder open of the .app starts a *second* copy (two MenuBarExtras). The `flock` guard only prevents double state-*writes*, not two running UIs. Fix: add a real single-instance handshake (bundle-id `NSRunningApplication` check → activate-existing-and-exit) and hand off cleanly at onboarding end (the onboarding instance `exit`s after `register()` so launchd owns the lifecycle from then on).
- **`KeepAlive=true` defeats the menubar "Quit" control (and pause).** §Onboarding 4 / §Components 1 ("quit") / §Tech stack. Unconditional KeepAlive makes launchd respawn the app the instant the user chooses Quit, so the control is a no-op and the app becomes unquittable. Fix: specify KeepAlive as conditional (restart only on `Crashed`/abnormal exit, e.g. `KeepAlive={SuccessfulExit=false}`) so a clean user Quit stays dead, and/or route Quit through `SMAppService.unregister()`/bootout; state this in M4 acceptance alongside the crash-restart check.

## Medium
- **Editing client_id in Settings still silently invalidates stored tokens with no forced re-auth (R2 carry, unaddressed).** §Components 9 ("client_id … re-editable") vs §Components 5 (refresh token bound to the issuing client_id). A rotated refresh token 400s under a new client_id → silent auth death. Fix: changing client_id must clear Keychain tokens + persisted playlist ID and drive the "Reconnect Spotify" re-auth path.
- **Liked Songs dedup is track-ID-only, contradicting the "ISRC-aware" claim (R2 carry, unaddressed).** §Dedup strategy source 2 (`GET /v1/me/tracks/contains?ids=`) keys on track ID only, so a same-ISRC re-release already in Liked Songs is re-added. Fix: state Liked Songs dedup is ID-only, or make the full-library ISRC scan the opt-in path (as done for owned playlists).

## Low
- **`playlist-modify-public` scope is unnecessary (R2 carry).** §Components 5 scopes — the playlist is created private; drop it to keep the consent screen minimal unless public playlists are supported.
- **BYO Connect step has no validation for a mistyped client_id / mismatched redirect URI (R2 carry).** §Onboarding 3 / §Components 5 — both surface as opaque web-sheet failures; validate the client_id/redirect round-trip in the Connect step with a targeted error.

## Impl-note
- **Re-auth presentation anchor** — the launchd-started, LSUIElement, windowless process must materialize a window + `presentationContextProvider` before `ASWebAuthenticationSession` for the "Reconnect Spotify" path (§Components 1 & 5).
- **OAuth `state` (CSRF)** — generate + verify a `state` param on the ASWebAuthenticationSession round-trip (§Components 5).
- **callbackURLScheme consistency** — `ASWebAuthenticationSession(callbackURLScheme:)` takes bare `friendlist`, while dashboard/Info.plist register `friendlist://auth-callback`; keep the three consistent (§Components 5, §Onboarding 3).
- **Notarization entitlements** — enumerate Hardened Runtime + secure timestamp entitlements (network client, Keychain, app-sandbox-off for FDA) and ensure the bundled `Contents/Library/LaunchAgents/*.plist` is inside the signed bundle (§Distribution).
- **Sparkle update ↔ SMAppService.agent** — after a Sparkle (v2) in-place update, plan to re-register the agent so launchd runs the new binary, and confirm the Developer ID designated requirement stays stable so the FDA/TCC grant survives version bumps (§Distribution, §v2).
