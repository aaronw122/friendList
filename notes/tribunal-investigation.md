# Investigation: Onboarding scan-before-Spotify reorder is logically correct and complete, with one latent back-navigation bug and one stale comment

## Question
Review the just-completed onboarding reorder in the FriendList macOS app. The onboarding step machine was changed so the chat SCAN runs BEFORE Spotify setup. New numbering: 0=Home, 1=Welcome, 2=PickChat, 3=Scanning, 4=SpotifyKeys, 5=OAuthConsent, 6=Customize, 7=Creating, 8=AllSet (previously Scanning was 5 and SpotifyKeys/OAuth were 3/4). Is the reorder correct and complete, and did it break the state machine, navigation (back button + swipe), the top progress bar, the earlier code-review fixes, or the second-run "create another" path?

## Key Findings

### 1. Forward flow is fully wired and lands on the intended screens — CORRECT (high)
Each screen's primary action advances by exactly one step, and the container switch maps steps to screens 1:1.
- Welcome(1) `PrimaryButton { state.advance() }` — `WelcomeView.swift:32` → 2
- PickChat(2) `onPrimary: { state.advance() }` — `PickChatView.swift:57` → 3
- Scanning(3) `state.advance()` after `performScan()` — `ScanningView.swift:98-103` → 4
- SpotifyKeys(4) `onPrimary: { state.advance() }` — `SpotifyKeysView.swift:48` → 5
- OAuth(5) `connectSpotify()` → `advance()` — `OAuthConsentView.swift:55-57`, `OnboardingState.swift:245` → 6
- Customize(6) `onPrimary: { state.advance() }` — `CustomizeView.swift:82` → 7
- Creating(7) `createPlaylist()` → `completeCreation()` → `go(to: 8)` — `CreatingView.swift:27`, `OnboardingState.swift:276,339`
- AllSet(8) `goHome()` → `go(to: 0)` — `AllSetView.swift:42`, `OnboardingState.swift:352`
The `stepScreen` switch (`OnboardingContainer.swift:80-89`) matches the new numbering exactly.

### 2. `canAdvance` still gates only step 2 — CORRECT (high)
`var canAdvance: Bool { step != 2 || pickedID != nil }` (`OnboardingState.swift:123`). Step 2 is still PickChat, so the "must select a chat" gate is on the right screen. No other step is gated.

### 3. `name` is seeded correctly even though Customize now follows OAuth — CORRECT (high)
`seedNameIfNeeded()` sets `name = selectedChatName` when empty (`OnboardingState.swift:368-370`), fired from `CustomizeView.onAppear` (`CustomizeView.swift:86`). `selectedChatName` derives from `pickedID` set at step 2 (`OnboardingState.swift:118-119`), which is unaffected by the OAuth detour. Seeding works the same as before; moving Customize later in the flow does not touch its inputs.

### 4. Scan-before-auth data dependencies are all satisfied — CORRECT (high)
- `performScan()` needs `pickedChat?.guid` from step 2 — available at step 3 (`OnboardingState.swift:189`).
- `createPlaylist()` needs `connected` — set at OAuth step 5, before Creating step 7. Satisfied.
- Nothing between Scanning(3) and Creating(7) depends on Spotify being connected: SpotifyKeys(4) only collects `clientId`, OAuth(5) authorizes, Customize(6) only edits name/desc.
- `scannedTrackURIs` is populated in `performScan` (`OnboardingState.swift:215`) and read in `createPlaylist` (`:264`). Nothing in steps 4/5/6 clears it. Only `createAnother()` clears it (intentional reset). So it is intact at Creating time.

### 5. Progress bar is monotonic across the real forward path — CORRECT (high)
Table `[0,0,0.16,0.32,0.50,0.66,0.80,0.92,1.0]` indexed by `step` (`OnboardingState.swift:127`). Because the flow now visits steps in strict numeric order 2→3→4→5→6→7→8, the fraction is 0.16→0.32→0.50→0.66→0.80→0.92→1.0 — strictly increasing. The reorder made the visual sequence trivially monotonic (no re-mapping needed).

### 6. "Create another" second run works and skips re-auth — CORRECT (high)
`createAnother()` (`OnboardingState.swift:355-365`) resets `pickedID, chatSearch, scannedTrackURIs, youtubeCount, found, name, scanPct, createPct` and goes to step 2.
- Scanning(3) is a fresh view (recreated via `.id(state.step)`), `ran=false`, re-scans the new chat.
- SpotifyKeys(4): `clientId` preserved from run 1, primary enabled, advances fine.
- OAuth(5): `connectSpotify()` short-circuits on `connected==true` — `if connected { if step == fromStep { advance() }; return }` (`OnboardingState.swift:231-233`). `fromStep == step == 5`, so it advances to 6 without re-auth. Correct.
- Customize(6): `name` was reset, so it reseeds from the new chat.
- Creating(7): `createInFlight` was released via `defer` in run 1, `createPct` reset — fine.
No user-visible stale-state leak: `lastCreatedURL` is not reset by `createAnother` but is overwritten in `completeCreation` (`:332`) before AllSet(8) renders, so run 1's URL never shows. (`desc` is also not reset — a run-1 custom description carries into run 2. Cosmetic, likely intended, not a bug.)

### 7. All earlier review fixes are intact — CORRECT (high)
- `createInFlight` re-entry guard: present (`OnboardingState.swift:79,256-258`).
- Persistence 1:1 mapping: `completeCreation` matches by `spotifyID` first, `persistAllPlaylists` writes each row's own ids (`:323-326,344-349`).
- `accessPollTask` cancel: `cancelAccessPolling()` (`:151-154`) called from `PickChatView.onDisappear` (`PickChatView.swift:62`).
- Stale-advance guards: ScanningView now guards `state.step == 3` (`ScanningView.swift:102`); `connectSpotify` uses `fromStep` (`OnboardingState.swift:230,232,245`).
- Refresh-token guard / loopback server / canRead empty-table fix live in `Sources/Backend/*` and `SpotifyService`, which the reorder did not touch.

### 8. No stale OLD step numbers remain anywhere in Sources/ — COMPLETE (high)
Grepped `state.step`, `step ==/>=/</>`, `go(to:`, `min/max(step`, `to: N`, `== N` across `Sources/`. Every hardcoded step number matches the new numbering:
- Container gates `step >= 2` / `step < 2` for physics fade, progress bar, and Back overlay — correct (2–8 are the in-flow steps).
- `progressFraction` table clamps to 0…8; `advance` clamps to `min(step+1, 8)`; `back` uses `case 2 -> 1` and `default -> max(step-1, 1)`; `completeCreation -> go(to: 8)`; `goHome -> go(to: 0)`; `createAnother -> go(to: 2)`. All correct.
- ScanningView's guard is `step == 3` — correct.
No leftover `step == 4/5`, `go(to: 4)`, or the removed `case 6: go(to: 4)` special case exist. Files outside Onboarding (`Persistence.swift`, `SQLiteReadOnly.swift`) only use `didOnboard` / SQLite `step`, unrelated to the machine.

### 9. LATENT BUG — Back into Scanning(3) re-runs the scan and auto-bounces forward (medium-high)
`canGoBack` is `(2...7)` (`OnboardingState.swift:299`) and `back()` from SpotifyKeys(4) does `go(to: 3)` (`:305`). Scanning is now step 3, sitting *inside* the back-navigable range. When you Back (or swipe) from SpotifyKeys(4) to Scanning(3):
1. `.id(state.step)` recreates `ScanningView` fresh, so `@State ran = false`.
2. `.task` runs `runScan()`: `!ran` passes → `performScan()` re-reads chat.db and repopulates `scannedTrackURIs` → sleeps 400ms.
3. Guard `state.step == 3` is still true (user is sitting on it) → `state.advance()` → `go(to: 4)`.

Net effect: pressing Back on SpotifyKeys shows a Scanning flash and then bounces the user right back to SpotifyKeys. Reaching PickChat(2) via Back requires pressing Back a second time during the scan window (before auto-advance), which is racy — on a small chat the scan finishes almost instantly, so it is effectively impossible to Back out of SpotifyKeys to the chat picker.

This is a regression newly introduced by the reorder: in the old layout Scanning was step 5, and the now-removed `case 6: go(to: 4)` special case existed specifically to prevent re-entering the auto-advancing Scanning step on Back. Moving Scanning to 3 without an equivalent guard reintroduces exactly that hazard at the 4→3 boundary. Data correctness is NOT affected (the re-scan is idempotent and repopulates state correctly); this is a navigation/UX defect.

Suggested fix options: skip Scanning on backward navigation (e.g. `case 4: go(to: 2)` in `back()`, mirroring the old special-case pattern), or have `ScanningView` only auto-advance when it wasn't entered via a back gesture.

### 10. Pre-existing (not reorder-caused) note — Creating(7) has no step guard around completeCreation (low)
Unlike `connectSpotify` (which uses `fromStep`), `createPlaylist`/`completeCreation` do not check the current step before `go(to: 8)` (`OnboardingState.swift:276,339`). If the user Backs out of Creating(7)→Customize(6) while the network create is in flight, completion still yanks them to AllSet(8). This predates the reorder (numbering is irrelevant to it) and is out of scope, but flagged for completeness.

### 11. Stale comment, not a logic bug (high)
`ScanningView.swift:103`: `state.advance() // → Customize (step 6)`. After the reorder, advance from step 3 goes to SpotifyKeys (step 4), not Customize. The code is correct; only the trailing comment is wrong and should read "→ SpotifyKeys (step 4)". (`CreatingView.swift:26` comment "→ step 8" is still accurate.)

## Conclusion
The reorder is logically CORRECT and COMPLETE (high confidence). The state machine, forward flow, `canAdvance` gate, name seeding, scan/auth data dependencies, progress-bar monotonicity, the "create another" second run, and all earlier code-review fixes survive the renumbering intact, and no stale OLD step numbers remain anywhere in `Sources/`. The build being green is consistent with the code being sound.

Two issues the build could not catch:
- One genuine latent navigation bug (Finding 9, medium-high): Back/swipe from SpotifyKeys(4) re-enters the auto-advancing Scanning(3) step and bounces forward, effectively blocking Back-to-PickChat. This is a direct consequence of moving Scanning into the middle of the back-navigable range while removing the special case that used to guard against re-entering it. Recommend a small `back()` fix.
- One stale comment (Finding 11) and one pre-existing, out-of-scope guard gap (Finding 10).

Overall: correct and complete reorder; fix the Scanning back-entry bounce and the stale comment.

## Evidence Trail
- Sources/Onboarding/OnboardingState.swift — step var (:34), canAdvance (:123), progressFraction (:126-129), performScan (:187-222), connectSpotify (:228-250), createPlaylist (:254-281), go/advance (:285-295), canGoBack/back (:299-307), completeCreation/persistAllPlaylists (:311-349), goHome (:352), createAnother (:355-365), seedNameIfNeeded (:368-370), init (:81-109)
- Sources/Onboarding/OnboardingContainer.swift — physics `step >= 2` (:19-21), phaseContent (:64-77), stepScreen switch (:79-90), progress bar gate (:32-35), Back overlay `canGoBack` (:39-48), swipe gesture (:54-61)
- Sources/Onboarding/Screens/ScanningView.swift — runScan + `step == 3` guard (:93-104), stale comment (:103)
- Sources/Onboarding/Screens/SpotifyKeysView.swift — advance on primary (:48)
- Sources/Onboarding/Screens/OAuthConsentView.swift — connectSpotify on primary (:55-57)
- Sources/Onboarding/Screens/CustomizeView.swift — advance + seedNameIfNeeded onAppear (:82-86)
- Sources/Onboarding/Screens/CreatingView.swift — runCreate/createPlaylist (:22-28)
- Sources/Onboarding/Screens/AllSetView.swift — createdURL/goHome (:14-16,42)
- Sources/Onboarding/Screens/PickChatView.swift — advance + cancelAccessPolling (:57,62)
- Sources/Onboarding/Screens/WelcomeView.swift — advance (:32)
- Sources/Onboarding/Screens/HomeView.swift — createAnother (:37)
- Grep sweep of Sources/ for hardcoded step numbers (all accounted for; none stale)
