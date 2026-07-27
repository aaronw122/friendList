# Task: Reorder onboarding so the chat SCAN runs BEFORE Spotify setup

You are editing a native SwiftUI macOS app (FriendList) at the current working directory. Do NOT use the web. Make ONLY the changes below, then build and report. Keep the visual design of every screen unchanged — this is purely a step-order change in the state machine.

## Why
Today the flow forces Spotify login before the user's chat is even scanned. We want: pick chat → scan the chat (find songs) → THEN set up Spotify → build the playlist. This lets M1 (chat.db reading) be validated without Spotify.

## Current step numbering (OnboardingState.step)
```
0 = Home
1 = Welcome
2 = PickChat
3 = SpotifyKeys      <-- Spotify
4 = OAuthConsent     <-- Spotify
5 = Scanning         <-- the scan
6 = Customize
7 = Creating
8 = AllSet
```

## NEW step numbering (target)
```
0 = Home
1 = Welcome
2 = PickChat
3 = Scanning         <-- MOVED UP (was 5)
4 = SpotifyKeys      <-- was 3
5 = OAuthConsent     <-- was 4
6 = Customize        (unchanged number)
7 = Creating         (unchanged)
8 = AllSet           (unchanged)
```
Only three screens change step numbers: Scanning 5→3, SpotifyKeys 3→4, OAuthConsent 4→5. Customize/Creating/AllSet keep 6/7/8. The Customize→Creating adjacency is preserved.

## Exact edits

### 1. `Sources/Onboarding/OnboardingContainer.swift`
In the `stepScreen` switch, remap the cases to the NEW numbering:
```swift
case 2: PickChatView()
case 3: ScanningView()
case 4: SpotifyKeysView()
case 5: OAuthConsentView()
case 6: CustomizeView()
case 7: CreatingView()
case 8: AllSetView()
```
Leave everything else in that file (physics opacity `step >= 2`, progress bar, Back overlay, swipe gesture) unchanged.

### 2. `Sources/Onboarding/OnboardingState.swift`
- Update the top-of-file doc comment describing the step order to the NEW numbering above.
- `back()`: REMOVE the special case `case 6: go(to: 4)` (it existed to skip the scan when going back from Customize; the scan is now earlier so it's obsolete). Result:
```swift
func back() {
    switch step {
    case 2: go(to: 1)                 // Pick chat → Welcome
    case 0, 1: break                  // no back from Home / Welcome
    default: go(to: max(step - 1, 1))
    }
}
```
- `progressFraction`: the table maps step→fraction (index 0...8). Keep 9 entries, strictly increasing from step 2 to 8. Use:
```swift
let table: [Double] = [0, 0, 0.16, 0.32, 0.50, 0.66, 0.80, 0.92, 1.0]
```
- Leave `advance()`, `canAdvance`, `canGoBack` (2...7), `completeCreation` (go to 8), `createAnother` (go to 2), `goHome` (go to 0), `seedNameIfNeeded` UNCHANGED.

### 3. `Sources/Onboarding/Screens/ScanningView.swift`  ⚠️ CRITICAL
There is a hardcoded step guard in `runScan()`:
```swift
guard !Task.isCancelled, state.step == 5 else { return }
```
The scanning step is now **3**, so change `state.step == 5` to `state.step == 3`. If you miss this, the scan will never advance. Leave the rest of the file unchanged.

### 4. Cosmetic comment fixes (do these so comments don't lie, but they are not functional)
- `Sources/Onboarding/Screens/SpotifyKeysView.swift`: header comment says "Step 3" → "Step 4".
- `Sources/Onboarding/Screens/OAuthConsentView.swift`: "Step 4" → "Step 5".
- `Sources/Onboarding/Screens/ScanningView.swift`: "Scanning (step 5)" → "Scanning (step 3)".
- Do NOT change any layout, copy shown to users, or logic in these files.

## Do NOT touch
- Any file under `Sources/Backend/`, `Sources/Physics/`, `Sources/DesignSystem/`.
- `SpotifyConfig.swift`, `project.yml`, `Info.plist`, entitlements.
- The actual UI/layout of any screen.

## Build & verify (REQUIRED before you report)
The project uses a stable signing keychain. Run exactly:
```
security unlock-keychain -p friendlist "$HOME/Library/Keychains/friendlist-signing.keychain-db"
xcodegen generate
xcodebuild -project FriendList.xcodeproj -scheme FriendList -configuration Debug -derivedDataPath /tmp/claude/friendlist-dd build 2>&1 | tail -5
```
It MUST end with `** BUILD SUCCEEDED **`. If there are errors, fix them and rebuild until green.

## Report back
Write a short summary to `notes/reorder-result.md` containing: the files you changed, confirmation the build succeeded, and any deviations from this spec. Do not launch the app.
