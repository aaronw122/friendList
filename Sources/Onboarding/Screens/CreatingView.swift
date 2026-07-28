import SwiftUI

// MARK: - Creating (step 7)

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
        guard !ran else { return }
        ran = true
        await state.createPlaylist()
    }
}
