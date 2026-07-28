import Foundation

// COORDINATION STUB — delete on integration with C1.
// C1 implements the real OnboardingState.startLaunchSyncIfOnboarded() in
// Sources/Onboarding/OnboardingState.swift. This default keeps the C2 branch building on its
// own; the duplicate definition at merge time is the intended signal to drop this one file.
extension OnboardingState {
    @MainActor func startLaunchSyncIfOnboarded() {}
}
