# Adversarial Integration/Concurrency Review — FriendList onboarding + backend

Scope: how the wired backend meets the existing step machine and SwiftUI screens.
Swift 5 language mode (project.yml SWIFT_VERSION 5.0), macOS 14, non-sandboxed.

---

## F1 (MAJOR, borderline critical) — `persistPlaylists` corrupts every prior playlist's `spotifyID` and `chatGUID` on each new save; `loadPlaylists` then discards both fields anyway

Files: `Sources/Onboarding/OnboardingState.swift:300-307` (save), `:89-91` (load), `:15-21` (Playlist model).

The in-memory `Playlist` (`:15-21`) has **no** `spotifyID` and **no** `chatGUID`. Those live only on
`SavedPlaylist`, and `persistPlaylists` reconstructs them from the *current* onboarding
context for **all** rows:

```swift
let saved = lists.map { l in
    SavedPlaylist(spotifyID: l.name == (name.isEmpty ? selectedChatName : name) ? newSpotifyID : "",
                  name: l.name, songCount: l.songCount, chatName: l.chatName,
                  chatGUID: pickedChat?.guid ?? "", externalURL: l.externalURL)  // <- same guid on every row
}
```

Repro:
1. Create playlist for chat A (name "A"). Persisted: `{spotifyID: idA, chatGUID: guidA}`. Correct.
2. Home → "Create a new one" → chat B (name "B"). `completeCreation` → `persistPlaylists`.
   Now for row A: `"A" == "B"` is false → `spotifyID = ""`, and `chatGUID = pickedChat.guid = guidB`.

Result: playlist A is re-persisted with an **empty spotifyID** and **chat B's guid**. Every
previously created playlist is repointed to the latest onboarded chat and loses its Spotify id.
`chatGUID` is what the M2 background watcher keys off of, so this silently mis-wires which chat
each old playlist syncs from.

Compounding: `loadPlaylists()` (`:89-91`) maps `SavedPlaylist → Playlist` and **drops** `spotifyID`
and `chatGUID` entirely. So even a correctly-saved single playlist loses those on the next launch —
the fields are effectively write-only. Structural: the model can't round-trip per-row identity.

---

## F2 (MAJOR) — No path back to Home on relaunch; `didOnboard` is written but never read

Files: `OnboardingState.swift:31` (`var step = 1`), `:296` (writes `didOnboard = true`), `:310` (only `go(to:0)`), `AllSetView.swift:41`.

`init` restores `lists` from Persistence but always leaves `step = 1` (Welcome). `Persistence.didOnboard`
is set true at `completeCreation` but is **never read** anywhere (confirmed by grep). `go(to: 0)`
(Home) is called **only** from `goHome()`, which is invoked **only** from AllSetView (step 8).

Repro: onboard + create a playlist, quit, relaunch. App opens on the Welcome screen. There is no
"you're already set up" branch and no Home entry point — the restored `lists` are only rendered by
HomeView (step 0), which the user can reach only by walking the entire onboarding + create flow
again. The persisted Home is unreachable for a returning user. The one flag that exists to fix this
(`didOnboard`) is ignored.

---

## F3 (MAJOR) — Re-entrancy: swipe-back during "Creating" still creates the playlist and yanks to step 8; a re-tap creates a DUPLICATE Spotify playlist

Files: `CreatingView.swift:22-28`, `OnboardingState.swift:228-250` (`createPlaylist` — no in-flight guard).

`createPlaylist` has **no** re-entrancy guard (contrast `connectSpotify` `:212` which guards `!connecting`).
`CreatingView.ran` is per-view `@State` and resets whenever the step-5/6/7 view is recreated via
`.id(state.step)` (OnboardingContainer:26).

Repro A (unexpected jump): On step 7, `createPlaylist` awaits the actor's network call (not cancellable —
no `Task.isCancelled` checks in SpotifyService). Swipe right (global gesture, `canGoBack` true for 2…7)
→ `back()` → step 6. The `.task` is cancelled but the actor call finishes anyway → `completeCreation()`
→ `go(to: 8)`. User is editing the name on Customize and is abruptly thrown to "All set."

Repro B (duplicate on Spotify): during that in-flight create, back on step 6 tap "Create playlist"
(`advance` → step 7) → fresh CreatingView → **second** `createPlaylist` call → a second identical
playlist is created in the user's Spotify account. Local `lists` dedups on name+chatName
(`:288`) so Home shows one, but Spotify now has two.

---

## F4 (MAJOR) — Stale `advance()` after a cancelled scan: swipe-back during "Scanning" throws the user forward again and re-runs the scan

Files: `ScanningView.swift:94-101`, `OnboardingState.swift:169-204`.

```swift
await state.performScan()
try? await Task.sleep(for: .milliseconds(400))   // cancelled task -> throws, swallowed by try?
state.advance()                                   // <- runs unconditionally
```

`performScan` awaits a `withCheckedContinuation` wrapping a `DispatchQueue.global` scan that is **not**
cancellable; the continuation always resumes. When the user swipes back on step 5, the `.task` is
cancelled, but: the background scan runs to completion → `performScan` returns → `Task.sleep` throws
`CancellationError` → swallowed by `try?` → `state.advance()` fires. `advance()` is relative to the
*current* step. Repro: start scan (step 5), swipe back to step 4 (OAuth). When the scan finishes,
`advance()` runs from step 4 → `go(to: 5)`, snapping the user back into Scanning; the recreated
ScanningView (`ran=false`) then re-runs `performScan`. Missing `guard !Task.isCancelled` before `advance()`.

(Same class of bug in OAuth: `OAuthConsentView.swift:56` fires `connectSpotify` from an untethered
`Task {}` in the button closure — not the `.task` modifier — so swiping back to step 3 does not cancel
it; on browser success `connectSpotify` calls `advance()` from step 3 and pulls the user forward.)

---

## F5 (MAJOR) — "Create another" forces a full Spotify re-authorization every time despite `connected == true`

Files: `OnboardingState.swift:313-319` (`createAnother` → step 2), `OAuthConsentView.swift:55-57`, `connectSpotify` `:209-225`.

`createAnother` comment says "preserving auth + keys," but it only preserves the *values* (`clientId`,
`connected`); the linear flow still marches 2 → 3 (SpotifyKeysView) → 4 (OAuthConsentView) → 5. The OAuth
screen's primary button unconditionally calls `connectSpotify()`, which has **no already-connected
short-circuit** — it re-runs `auth.authorize()`, reopening the browser and spinning up the loopback
NWListener for a redundant full OAuth round-trip on every additional playlist. The "preserving auth"
intent is defeated.

---

## F6 (MAJOR) — `createAnother` doesn't reset `name`; second playlist is mis-named with the FIRST playlist's name

Files: `OnboardingState.swift:313-319` (resets only `pickedID`, `chatSearch`, `scannedTrackURIs`, `found`), `:322-324` (`seedNameIfNeeded`), `CustomizeView.swift:86`.

`name` is not cleared on "create another." `seedNameIfNeeded()` only seeds when `name.isEmpty`, so on
the second run it does nothing and the Customize field is pre-filled with run 1's name. Repro: run 1
picks "the boys" (name becomes "the boys"), finish; Create another → pick "brunch club" → Customize
shows "the boys". If the user doesn't hand-edit, `createPlaylist` sends `name = "the boys"` to Spotify
while `chatName = "brunch club"`, and Home/persistence record the mismatch. (`desc` is likewise not
reset, but reusing the default description is defensible.)

---

## F7 (MINOR) — `resumeAtPicker` written but never read: the FDA relaunch-resume mechanism is dead

Files: `OnboardingState.swift:133` / `:146` (set/clear), `Persistence.swift:22-25`, `FullDiskAccess.swift:8` (comment claims "re-probe on launch").

Granting Full Disk Access frequently makes macOS relaunch the app (TCC). `requestAccess` sets
`Persistence.resumeAtPicker = true` precisely for this, and the comment says the marker "covers the
relaunch case," but nothing reads it at launch. On relaunch the app opens at step 1 (Welcome), not the
picker, discarding the user's place. The whole resume marker is non-functional.

---

## F8 (MINOR) — `recordSeen` is write-only for this build

Files: `OnboardingState.swift:293-295`, `Persistence.swift:49-59`.

`completeCreation` records the per-chat seen URI set, but `Persistence.seenTracks(...)` is never read
anywhere. The scan's dedup (`MessagesReader.swift:149-159`) is per-run/in-chat only and never consults
the persisted seen-set, so cross-run dedup does nothing today. Acceptable if this is reserved for the
not-yet-present M2 background sync, but worth flagging as unused wiring.

---

## F9 (MINOR) — AllSetView can show the wrong playlist link after a dedup-skipped create

Files: `AllSetView.swift:13-15`, `OnboardingState.swift:288`.

`createdURL = state.lists.last?.externalURL`. If a create's name+chatName collides with an existing row,
`completeCreation` skips the append, so `lists.last` is a *different* (older) playlist. The "Open in
Spotify" button and link card then point at the old playlist even though a new one was created on Spotify.

---

## Areas that are genuinely solid

- **`ran` guard is NOT a permanent block.** `.id(state.step)` (OnboardingContainer:26) gives each entry
  to step 5/7 a fresh view with `ran = false`, so a second scan/create runs correctly. The guard only
  protects against same-identity reappearance. Good.
- **No data races at runtime (Swift 5 warnings only).** In `performScan` the `DispatchQueue.global`
  closure touches only the local `let reader` and the continuation; all `@Observable` mutations are
  re-dispatched to `DispatchQueue.main` (`:183-187`, `:191`). In `createPlaylist` the `@Sendable`
  progress closure mutates state only inside `Task { @MainActor }` (`:239-242`). Capturing non-Sendable
  `self` produces warnings under Swift 5 (would be errors under Swift 6 / strict concurrency) but no
  actual concurrent access to the observable properties. `MessagesReader`/`SampleMessagesReader` are
  value types opening their own SQLite connections, so off-main scans don't share mutable state.
- **No continuation leaks.** `performScan` resumes the continuation on both success and catch
  (`:189`, `:193`); `LoopbackAuthServer.finishOnce` (`:31-37`) and `withTimeout` (`:164-175`) guard
  against double/absent resume; `connectSpotify` guards `!connecting`.
- **Preview path.** There are **no `#Preview` blocks anywhere** in the project (grep-confirmed), so the
  `XCODE_RUNNING_FOR_PREVIEWS` special-casing in `init` is currently unexercised — it can't break a
  preview because none exist, and it can't leak into runtime (only Xcode sets that env var).
  `SampleMessagesReader.scan` guid parsing (`SampleMessagesReader.swift:25`) correctly maps
  `"sample-<i>"` → index → sample link count; solid for the sample guids.
- **NWListener vs entitlements.** The app is non-sandboxed (`entitlements` app-sandbox=false), so the
  `network.client`/`network.server` entitlements don't gate anything — `NWListener` binding
  `127.0.0.1:8888` works. `network.server` would only be required under App Sandbox. Hardened runtime
  (ON) doesn't block listening sockets. Sufficient as configured.
- **No dead custom-scheme references.** Nothing references a removed `callbackScheme`; `SpotifyConfig`
  uses the loopback `redirectURI` consistently across `SpotifyAuth`, `LoopbackAuthServer`, and the keys
  screen. No mock switch silently no-ops the real backend outside the (unused) preview branch.
