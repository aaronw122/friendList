import SwiftUI

/// Step 8 — "All set" completion screen. Renders inside the sheet (centered column).
struct AllSetView: View {
    @Environment(OnboardingState.self) private var state
    @Environment(\.openURL) private var openURL

    private var cardTitle: String {
        state.name.isEmpty ? state.selectedChatName : state.name
    }

    /// The playlist created in THIS run (not necessarily lists.last, since a
    /// re-created earlier playlist updates in place). Its externalURL opens Spotify.
    private var createdURL: String {
        state.lastCreatedURL
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("You're all set")
                .ui(30, 800, color: Palette.ink)
                .tracking(-0.03 * 30)
                .multilineTextAlignment(.center)

            Text("friendList is watching \(state.selectedChatName). Every song anyone drops in lands in the playlist within a minute.")
                .ui(14.5, 400, color: Palette.body)
                .lineSpacing(14.5 * 0.55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 10)

            linkCard
                .padding(.top, 20)

            PrimaryButton(title: "Open in Spotify") {
                let target = createdURL.isEmpty ? "https://open.spotify.com" : createdURL
                if let url = URL(string: target) { openURL(url) }
            }
            .padding(.top, 22)

            LinkButton(title: "Back to friendList", size: 12.5, color: Palette.body) {
                state.goHome()
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, SheetLayout.hInset)
    }

    private var linkCard: some View {
        HStack(spacing: 12) {
            StripeCover(size: 44, corner: 7, stripe: 6, period: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(cardTitle)
                    .ui(13.5, 700, color: Palette.fieldInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(createdURL.isEmpty
                     ? "open.spotify.com/playlist/…"
                     : createdURL.replacingOccurrences(of: "https://", with: ""))
                    .mono(12, 400, color: Palette.body)
                    .underline(true, color: Palette.body.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .fill(Palette.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
        .frame(maxWidth: 400)
    }
}
