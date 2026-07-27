# Friend List — Review r2: Product / Privacy / Onboarding UX (agent3)

Persona: Product / Privacy / Onboarding UX Reviewer

## Round-1 fix verification
- **C1 (single executable / menubar-only login item / FDA covers scanning):** Resolved at the architecture level, BUT the menubar-only change introduces a new onboarding-window/relaunch problem — see Critical below.
- **C2 (BYO client_id):** Applied, but creates new UX/consistency gaps (ordering, redirect URI, account identity) — see Must-fix/Medium below.
- **M2 (single-use rotating refresh tokens):** Genuinely resolved — Component 5 serializes refresh + atomic Keychain overwrite; M2 milestone verifies rotation. ✔
- **M6 (menubar attention/error state):** Genuinely resolved for auth revoked / FDA lost / playlist gone — Architecture + Components 1 & 5. ✔ (playlist-recovery *action* still thin — see Medium.)

## Critical
- **FDA grant terminates the app mid-onboarding; menubar-only relaunch has no step-resume and may not re-present the onboarding window.** §Onboarding "2. Scope" + Components §1: macOS kills the target process when Full Disk Access is toggled, and `didOnboard` is only set on screen 4. On relaunch the app is now `LSUIElement` menubar-only, so it starts at Welcome (state lost) and a background app's onboarding `WindowGroup` may not auto-foreground — the "Choose chats…" path can never reach a populated picker or complete. Fix: persist an onboarding-step marker, resume post-grant at the scope/picker screen, and explicitly `NSApp.activate` + present the onboarding window on relaunch when `!didOnboard`.

## Must-fix
- **Denied / never-granted FDA still has no failure state (carryover, unresolved).** Components §1 only "poll for access"; §Onboarding "2" has no denied/stuck copy. Fix: define an explicit "not granted — try again / can't continue without this" state with a graceful installed-but-paused end state.
- **Privacy claim still contradicts persisted retry queue (carryover, partial).** §Privacy "Local only" now qualifies with "beyond what filtering needs locally," but Components §8 persists **source chat + sender per retry entry** — that is retention for *retry*, not filtering, so the claim "never … contact identifiers beyond what filtering needs" is still false. Fix: either store only the track URI in the retry queue (drop chat/sender) or amend the privacy claim to admit chat/sender are persisted locally for retry.
- **Login-item registration can be disabled/require approval; menubar-only ambient promise breaks silently (carryover, elevated).** §Onboarding "4" + Components §1/4 register `SMAppService.mainApp` silently. If the user declines/disables it under System Settings → Login Items, the app never auto-launches and "never needs to be opened again" fails with no signal. Fix: detect `SMAppService.status != .enabled` and surface an "enable Friend List in Login Items" explainer/attention item.
- **BYO Premium + own-dev-app requirement is discovered on screen 3, AFTER the invasive FDA grant on screen 2.** §Onboarding "2"→"3": a non-Premium user (or one unwilling to create a dev app) grants Full Disk Access, then hits a dead end. Fix: gate/disclose the Premium + create-your-own-Spotify-app requirement on Welcome (or before the FDA grant) so the scary permission isn't spent on a dead-end flow.

## Medium
- **Cancelled / failed Spotify OAuth in onboarding still has no state (carryover).** §Onboarding "3" assumes success; Component 5's auth-error covers the *running* refresh path, not an onboarding `ASWebAuthenticationSession` cancel/error. Fix: define retry/cancel copy; Done unreachable until auth succeeds.
- **Deleted-playlist recovery action unspecified (carryover, partial).** M6/Architecture now flip to "Attention needed" on "playlist gone," but Components §1 says the item "reopens the relevant onboarding step" — there is no onboarding step for the playlist and re-auth won't recreate it. Fix: on 404, recreate the playlist and re-persist its ID (or a dedicated "recreate playlist" attention action).
- **No redirect-URI-mismatch error path (new, from BYO).** §Onboarding "3" tells users to add `friendlist://auth-callback` in their dashboard; if they skip it, OAuth fails with an opaque Spotify `redirect_uri` error. Fix: define an explicit "check the redirect URI in your Spotify app" error state on auth failure.
- **Dev-app-owner account must equal the Premium/auth account (new, from BYO).** Component 5 / §Onboarding "3": the account that creates the client_id must be the same Spotify account you authenticate with and it must be Premium; unstated → silent auth/permission failure if they differ. Fix: state "use the same Premium Spotify account for both."
- **Screen-2 grant copy still overclaims "stored" (carryover).** §Onboarding "2" copy: "never uploaded, stored, or sent anywhere." Given the local seen-set + retry queue on disk, "stored" is misleading. Fix: reword to "never leaves this Mac."

## Low
- **Welcome hero still "Spotify mark" vs fusion branding (carryover).** §Onboarding "1" vs §Branding. Fix: use the Messages+Spotify fusion mark on Welcome.
- **Scope question still says "certain group chats" but picker lists DMs (carryover).** §Onboarding "2". Fix: reword to "…or only certain chats?"
- **FDA poll still has no timeout/skip nudge (carryover).** Components §1. Fix: after N seconds show "still waiting / open Settings again."
- **Persistent "nothing leaves your Mac" footer tensions screen 3 (new).** §Onboarding footer is on all four screens, yet screen 3 has you open Spotify's developer dashboard in a browser and paste a client_id. Fix: footer copy that survives the browser step (e.g. "your messages never leave your Mac").

## Impl-note
- Verify whether a dev-app *owner* must add themselves under the app's User Management to authenticate (Spotify Development Mode) — confirm at M2; if required, the "no allowlist / no email" claim needs softening.
- Exact TCC probe + `x-apple.systempreferences:` FDA deep-link target per macOS version.
- Casing "friend list" (Welcome title) vs "Friend List" (playlist/app) — pick one (carryover).
