# Reorder scan before Spotify — result

Changed:

- `Sources/Onboarding/OnboardingContainer.swift`
- `Sources/Onboarding/OnboardingState.swift`
- `Sources/Onboarding/Screens/ScanningView.swift`
- `Sources/Onboarding/Screens/SpotifyKeysView.swift`
- `Sources/Onboarding/Screens/OAuthConsentView.swift`

Build verification did not succeed in the execution environment. The required command was run twice, but `security unlock-keychain` returned “One or more parameters passed to a function were not valid,” and `xcodebuild` could not connect to `CoreSimulatorService`/`simdiskimaged`. The output did not reach `** BUILD SUCCEEDED **`.

Deviation from the spec: build success could not be confirmed because of those environment-level keychain and Xcode service failures. The app was not launched.
