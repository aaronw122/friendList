import SwiftUI

// MARK: - Creating (step 7)

struct CreatingView: View {
    @Environment(OnboardingState.self) private var state
    @State private var ran = false

    var body: some View {
        ZStack {
            if let message = state.createError {
                errorBlock(message)
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
        guard !ran else { return }
        ran = true
        await state.createPlaylist()
    }

    // Retry resumes the partially built playlist instead of creating a duplicate.
    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Couldn't build the playlist")
                    .font(UIFont2.ui(28, 800))
                    .tracking(-0.03 * 28)
                    .foregroundStyle(Palette.ink)

                Text(message)
                    .font(UIFont2.ui(15, 500))
                    .foregroundStyle(Palette.body)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Try again",
                primaryEnabled: true,
                onPrimary: { Task { await state.createPlaylist() } }
            )
        }
    }
}
