import SwiftUI

struct WelcomeView: View {
    @Environment(OnboardingState.self) private var state
    @Environment(\.physicsBridge) private var physics

    @State private var showText = false
    @State private var showButton = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("friendList")
                    .font(UIFont2.ui(60, 800))
                    .tracking(-0.035 * 60)
                    .foregroundStyle(Palette.ink)
                    .shadow(color: .white.opacity(0.9), radius: 0, y: 2)

                Text("Turn songs from your group chat into a Spotify playlist")
                    .font(UIFont2.ui(17, 500))
                    .foregroundStyle(Palette.subheadWarm)
                    .lineSpacing(7)
                    .frame(maxWidth: 400)
                    .padding(.top, 20)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 37)
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 10)

            PrimaryButton(title: "Continue") { state.advance() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 262)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
        .onAppear {
            showText = false
            showButton = false
            physics.dropAll()
            revealTask?.cancel()
            revealTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { showText = true }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { showButton = true }
            }
        }
        .onDisappear { revealTask?.cancel() }
    }
}
