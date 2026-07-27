import SwiftUI

/// Step 1 — Welcome. Renders directly on the desk-and-objects background.
/// Matches the handoff exactly: text block anchored 87pt from the top, the CTA
/// anchored 212pt from the bottom (independent anchors, so the button doesn't
/// shift when the copy reflows). Wordmark + subhead + Continue only.
struct WelcomeView: View {
    @Environment(OnboardingState.self) private var state

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

            // CTA — 212pt from the bottom, independent of the text block.
            PrimaryButton(title: "Continue") { state.advance() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 212)
        }
    }
}
