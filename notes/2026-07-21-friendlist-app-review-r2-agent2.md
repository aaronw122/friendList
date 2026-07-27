# Friend List Plan Review R2 — Spotify OAuth/API + Distribution Specialist (r2-agent2)

Persona lens: ASWebAuthenticationSession PKCE + `friendlist://` redirect, BYO client_id, token storage/refresh, playlist bootstrap/add/dedup + scopes, ISRC, and macOS distribution (Developer ID / notarization / Gatekeeper / Spotify dev-quota).

## Round-1 fix verification
- **C1 (single executable) — RESOLVED.** §Architecture + §Components 1–2 collapse app+agent into one LSUIElement/`SMAppService.mainApp` login item; FDA grant covers in-process scanner; single-writer inherent (flock guards dup launch). New reliability side-effects flagged below.
- **C2 (BYO client_id) — RESOLVED.** §Onboarding 3, §Components 5, §Privacy, §Risks: no embedded id, no shared cap, no allowlist, no email; Premium called out. Dev-quota (~25-user cap / extended quota) is now moot — each user authenticates only themselves against their own dev-mode app (owner is 1 user, implicitly allowed).
- **M2 (rotating refresh token) — RESOLVED.** §Components 5 "Refresh-token rotation (critical)": serialized in-process refresh + atomic write-then-swap Keychain overwrite of the rotated token; M2 acceptance verifies persistence across refreshes.
- **M6 (menubar attention state) — RESOLVED.** §Components 1 & 5 + §Architecture: shared `@Observable` health state, icon swap + "Attention needed — Reconnect Spotify" reopening the relevant onboarding step on auth/FDA/playlist failure.

## Critical
- (none)

## Must-fix
- **App translocation breaks FDA grant AND login-item registration if first run happens from the DMG.** §Onboarding 2–4, §Distribution. Gatekeeper runs a quarantined app from a randomized read-only path; TCC (FDA) is keyed to path/cdhash and `SMAppService.mainApp` records that path — both are invalidated once the user later drags to /Applications, silently killing the "forever" scanner. Fix: onboarding must detect it isn't running from /Applications (or is translocated) and require the move to /Applications *before* requesting FDA or registering the login item.
- **No crash/exit recovery — `SMAppService.mainApp` only launches at login, not on crash.** §Architecture, §Components 1–2, §Milestones M4. Collapsing to one process (C1) removed launchd `KeepAlive`; if the single app process crashes or is quit, scanning is dead until next login/reboot, undermining the "zero taps forever" pillar. Fix: decide now — either register a `SMAppService.agent` plist (same bundled executable) with `KeepAlive` as a watchdog, or explicitly document that recovery is login-only, and reflect it in M4 acceptance.

## Medium
- **Editing client_id in Settings silently invalidates stored tokens with no forced re-auth.** §Components 9 (client_id "re-editable") vs §Components 5 (refresh token bound to a client_id). A refresh token issued under the old client_id will 400 under a new one → silent auth death. Fix: changing client_id must clear the Keychain tokens + playlist ID and drive the "Reconnect Spotify" re-auth path.
- **Liked Songs dedup is track-ID-only, contradicting the "ISRC-aware" claim (carried from R1, still unaddressed).** §Dedup strategy source 2 uses `GET /v1/me/tracks/contains?ids=`, which keys on track ID only — a re-release with same ISRC in Liked Songs won't be caught. Fix: state Liked Songs dedup is ID-only, or make a full-library ISRC scan the opt-in path (as done for owned playlists).

## Low
- **Confirm the app owner needs no self-add to dashboard User Management.** §Onboarding 3, §Risks. The BYO model relies on the owner being implicitly authorized in dev mode; document this so onboarding copy doesn't send users hunting for a "add yourself" step.
- **`playlist-modify-public` scope is unnecessary** — the "Friend List" playlist is created private (§Components 5 bootstrap). §Components 5 scopes. Fix: drop it unless public playlists are supported; keeps the consent screen minimal.
- **BYO onboarding has no error path for a mistyped client_id or missing/mismatched redirect URI.** §Onboarding 3, §Components 5. Both surface as opaque Spotify web-sheet failures. Fix: validate the client_id/redirect round-trip in the Connect step and show a targeted "check your client_id / redirect URI" error.

## Impl-note
- OAuth `state` param for CSRF is still unmentioned on the ASWebAuthenticationSession round-trip (§Components 5) — generate + verify it.
- `ASWebAuthenticationSession(callbackURLScheme:)` takes the bare scheme `friendlist`, while the dashboard/Info.plist register `friendlist://auth-callback` — keep the three consistent (§Components 5).
- Notarization needs Hardened Runtime + secure timestamp with entitlements for network client, Keychain, and the app-sandbox-off/FDA usage; enumerate them (§Distribution).
- Re-auth from the windowless menubar-only (LSUIElement) app needs an `ASWebAuthenticationSession` presentation anchor — the "reopen onboarding step" path must materialize a window/`presentationContextProvider` (§Components 1 & 5).
