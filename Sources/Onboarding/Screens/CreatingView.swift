import SwiftUI

// MARK: - Creating (step 7)

struct CreatingView: View {
    @Environment(OnboardingState.self) private var state
    @State private var hasStarted = false

    var body: some View {
        ZStack {
            if let message = state.createError {
                // Retry resumes the partially built playlist instead of creating a duplicate.
                RetryErrorView(title: "Couldn't build the playlist", message: message,
                               onRetry: { Task { await state.createPlaylist() } })
                    .transition(.opacity)
            } else {
                LoaderScaffold(
                    heading: "Building your playlist",
                    label: state.createLabel,
                    pct: state.createPct,
                    counter: nil
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.createError != nil)
        .task { await runCreate() }
    }

    @MainActor
    private func runCreate() async {
        guard !hasStarted else { return }
        hasStarted = true
        await state.createPlaylist()
    }
}
