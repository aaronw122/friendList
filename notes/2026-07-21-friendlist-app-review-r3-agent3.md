# Friend List — Review r3: Product / Privacy / Onboarding UX (agent3)

Persona: Product / Privacy / Onboarding UX Reviewer

## Round-2 fix verification
- **M3 (translocation / not-in-`/Applications` guard):** Resolved — §Onboarding "2" makes it the first gate before FDA; Component 1 + Distribution echo it. ✔ (placement nit → Low below)
- **M4 (`SMAppService.status` → "Enable in Login Items"):** Resolved — §Onboarding "4" + Component 1 raise the attention item on non-`.enabled`. ✔
- **M1 (SMAppService.agent, Program = own executable, RunAtLoad+KeepAlive):** One-code-identity/FDA claim is sound (launchd starting the bundle's own executable keeps bundle identity → TCC coverage). BUT RunAtLoad + KeepAlive on the *own* executable introduces two new conflicts — see Must-fix.
- **M8 (persist step marker, re-present after FDA relaunch):** Resolved for the *granted* path — §Onboarding "2" + Component 1. ✔ (denied path still dead-ends — see Medium.)
- **M7 (disclose Spotify account + BYO dev-app + Premium on Welcome, before FDA):** Resolved — §Onboarding "1" heads-up. ✔
- **Spotify write-gate:** Resolved — M2 first action is a live dev-mode `POST …/tracks`. ✔

## Critical
- (none)

## Must-fix
- **RunAtLoad immediately launches a *second* instance at registration, colliding with the running onboarding app.** §Onboarding "4" / Architecture / Component 2: at Done the LaunchServices-launched onboarding instance (A) registers the agent; `RunAtLoad` makes launchd start instance B of the same executable *right then*. B hits the `flock` and exits → `KeepAlive` respawns it → throttled respawn loop for the rest of the session, and it's ambiguous which instance is the "real" menubar app (KeepAlive only guards B, not A). The plan's flock mitigation prevents double-*writes* but not this. Fix: specify the handoff — after `register()` succeeds the onboarding instance MUST `NSApp.terminate` so launchd's RunAtLoad/KeepAlive instance becomes the sole owner (single menubar icon, KeepAlive guarding the live process).
- **Menubar "Quit" is defeated by `KeepAlive`.** Component 1 menubar lists "quit"; Component 5/Tech stack set `KeepAlive` unconditionally, so quitting the process makes launchd relaunch it immediately — "Quit" can't actually quit. Fix: "Quit" must `SMAppService…unregister()` / stop the agent (or relabel "Quit until next login" and use a conditional KeepAlive), not merely exit the process; keep pause/resume as the in-process flag.
- **Privacy claim still contradicts the persisted retry queue (section inconsistency, unresolved).** §Privacy "Local only" says "never … contact identifiers beyond what filtering needs locally," but Component 8's retry queue persists **source chat + sender** per entry — retention for *retry*, not filtering (a re-`POST` needs only the track URI). Fix: drop chat/sender from the retry entry (store only the track URI + attempt count), or amend the privacy line to admit chat/sender are persisted locally for retry.

## Medium
- **Denied / never-granted FDA still dead-ends, now compounded by the M8 resume.** §Onboarding "2" + Component 1 only "poll for access"; the M8 relaunch-resume explicitly assumes "FDA in hand." A user who denies (or never grants) FDA loops forever with no "can't continue / try again" branch and no paused end state. Fix: add an explicit not-granted state with retry + a graceful installed-but-paused exit.
- **Cancelled / failed onboarding OAuth has no state.** §Onboarding "3" assumes success; Component 5's auth-error covers the *running* refresh path, not an onboarding `ASWebAuthenticationSession` cancel/error (incl. `redirect_uri` mismatch from BYO). Fix: define cancel/retry copy; "Done" unreachable until auth succeeds.

## Low
- **Translocation guard sits mid-flow (start of screen 2) rather than pre-Welcome.** §Onboarding "2": the user sees Welcome, then a move-to-/Applications + relaunch, re-seeing Welcome — and possibly a second FDA relaunch on the same screen. Fix: run the guard on launch before Welcome so at most one relaunch precedes onboarding.
- **Playlist-gone recovery action still unspecified.** Component 1 "reopens the relevant onboarding step," but no onboarding step recreates a deleted playlist and re-auth won't (token still valid). Fix: on 404, recreate the playlist + re-persist ID (dedicated "recreate playlist" attention action).

## Impl-note
- Confirm TCC/FDA attribution when launchd starts the bundle's executable *directly* (bundle identity resolves from `Contents/MacOS/…` path) — already gated at M4.
- LaunchAgent `Program` is an absolute path; a later user move/rename of the .app leaves a stale path → silent no-launch. Re-validate/re-register the path on each app run.
- BYO: dev-app *owner* account must equal the Premium/auth account; surface the exact `friendlist://auth-callback` redirect-URI mismatch hint on auth failure (carryovers).
- Casing "friend list" (Welcome) vs "Friend List" (playlist/app) — pick one (carryover).
