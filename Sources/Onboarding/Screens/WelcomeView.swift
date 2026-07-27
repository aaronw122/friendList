import SwiftUI

/// Step 1 — Welcome. Renders directly on the desk-and-objects background.
/// Matches the handoff exactly: text block anchored 87pt from the top, the CTA
/// anchored 212pt from the bottom (independent anchors, so the button doesn't
/// shift when the copy reflows). Wordmark + subhead + Continue only.
struct WelcomeView: View {
    @Environment(OnboardingState.self) private var state

    // Staggered entrance: objects drop first, then the wordmark + subhead fade in,
    // then the Continue button.
    @State private var showText = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            // Text block — 87pt from the top.
            VStack(spacing: 0) {
                Text("friendList")
                    .font(UIFont2.ui(60, 800))
                    .tracking(-0.035 * 60)              // −0.035em
                    .foregroundStyle(Palette.ink)
                    .shadow(color: .white.opacity(0.9), radius: 0, y: 2)

                Text("Turn songs from your group chat into a Spotify playlist")
                    .font(UIFont2.ui(17, 500))
                    .foregroundStyle(Palette.subheadWarm)
                    .lineSpacing(7)                     // line-height ~1.45
                    .frame(maxWidth: 400)
                    .padding(.top, 20)                  // margin-top 20 (matches design)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 87)
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 10)

            // CTA — 212pt from the bottom, independent of the text block.
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
