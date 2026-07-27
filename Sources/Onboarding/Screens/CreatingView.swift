import SwiftUI

// MARK: - Creating (step 7)
//
// Identical layout to Scanning (LoaderScaffold), in accent purple, with no song
// counter line.

struct CreatingView: View {
    @Environment(OnboardingState.self) private var state
    @State private var ran = false

    var body: some View {
        LoaderScaffold(
            heading: "Building your playlist",
            label: state.createLabel,
            pct: state.createPct,
            counter: nil
        )
        .task { await runCreate() }
    }

    @MainActor
    private func runCreate() async {
        guard !ran else { return } // guard against re-running if the view reappears
        ran = true
        // Real Spotify create + populate; completeCreation() (→ step 8) runs on success.
        await state.createPlaylist()
    }
}
