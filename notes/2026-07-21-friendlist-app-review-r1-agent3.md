# Friend List — Review: Product / Privacy / Onboarding UX (r1-agent3)

Persona: Product / Privacy / Onboarding UX Reviewer

## Critical
_(none)_

## Must-fix
- **Denied / never-granted FDA has no path.** "Onboarding flow" §2 + "Components §1" only "poll for access" — if the user denies or never toggles FDA, onboarding hangs on screen 2 with no error state, skip, or retry copy. Fix: define an explicit "not granted yet / try again / can't continue without this" state and a way to reach a graceful stuck-screen (agent installed but paused).
- **Revoked Spotify token has no user-facing recovery, silently breaking the core promise.** "Product shape" / three pillars claim "never needs to be opened again," but the agent (Components §2, headless) stops adding when the refresh token is revoked/expired-permanently, with no notification channel. Fix: define a menubar attention/error state ("Reconnect Spotify") and how the headless agent signals the UI to prompt re-auth.
- **Privacy section contradicts what is persisted.** "Privacy (explicit)" says "message data is read, matched, and discarded — only Spotify track IDs are persisted," but "Components §8 State store" persists the retry queue with **source chat + sender** per entry (and SourceFilter persists `allowed_chats`/`allowed_handles`). Fix: reconcile — either qualify the privacy claim to admit chat/sender identifiers are stored locally for filtering/retry, or drop those fields from persisted state.
- **FDA grant typically forces app relaunch mid-onboarding; resume is unspecified.** "Components §1" + "Onboarding §2" request FDA via System Settings deep-link on screen 2, but macOS commonly restarts the app on grant. `didOnboard` is only set at the end, so a relaunch mid-flow's behavior (resume at scope screen vs. restart at welcome) is undefined. Fix: specify onboarding-step persistence so a post-grant relaunch resumes at the scope screen.

## Medium
- **Cancelled / failed Spotify auth has no described state.** "Onboarding §3 Connect Spotify" assumes success; no handling for user cancelling `ASWebAuthenticationSession` or OAuth error. Fix: define retry/cancel copy and that Done is unreachable until auth succeeds.
- **Deleted "Friend List" playlist has no recovery.** "Dedup"/"Components §5" persist the playlist ID; if the user deletes it in Spotify, adds 404 forever. Fix: on 404, recreate the playlist (or surface a menubar prompt) and re-persist the ID.
- **`SMAppService` registration may require user approval in Login Items; not surfaced.** "Onboarding §4 Done" installs the agent silently, but macOS 13 can require the user to enable it under System Settings → General → Login Items. Fix: add a "if disabled, enable Friend List in Login Items" explainer/detection.
- **Picker-reveal vs FDA-request ordering is ambiguous.** "Onboarding §2": tapping "Choose chats…" reveals a picker that needs FDA, and FDA is "requested here" — if the picker renders before the grant it is empty. Fix: specify FDA is granted before the conversation list is populated (gate the picker on the probe read succeeding).
- **Screen-2 grant copy overclaims vs persistence.** "Onboarding §2" copy: "never uploaded, stored, or sent anywhere." Given the local seen-set + retry queue (sender/chat) are stored on disk, "stored" is misleading. Fix: reword to "never leaves this Mac" rather than "never stored."

## Low
- **Welcome hero shows the "Spotify mark" but branding is a Messages+Spotify fusion mark.** "Onboarding §1" vs "Branding" — inconsistent hero asset. Fix: use the fusion mark on Welcome for brand coherence.
- **Scope question says "group chats" but the picker also lists DMs.** "Onboarding §2" question framing vs "DMs below" in the picker. Fix: reword question to "any chats — or only certain ones?"
- **FDA access-polling has no timeout/skip.** "Components §1" polls indefinitely. Fix: after N seconds show a "still waiting / open Settings again" nudge.

## Impl-note
- Casing inconsistency "friend list" (Welcome title) vs "Friend List" (playlist/app name) — pick one.
- Exact `x-apple.systempreferences:` deep-link target for the FDA pane — verify per macOS version at build time.
- FDA-detection poll interval / probe cadence — tune during implementation.
