import SwiftUI

struct WelcomeView: View {
    @Environment(OnboardingState.self) private var state

    @State private var showText = false
    @State private var showButton = false

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
            .padding(.top, 87)
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 10)

            PrimaryButton(title: "Continue") { state.advance() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 212)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeOut(duration: 0.5)) { showText = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.5)) { showButton = true }
        }
    }
}
