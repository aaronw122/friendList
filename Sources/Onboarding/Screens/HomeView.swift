import SwiftUI

struct HomeView: View {
    @Environment(OnboardingState.self) private var state
    @Environment(\.physicsBridge) private var physics

    var body: some View {
        GeometryReader { geo in
            panel
                .frame(width: min(430, geo.size.width * 0.88))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 34)
        }
        .onAppear { physics.dropAll() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if state.lists.isEmpty {
                Text("No playlists yet.")
                    .ui(13, 400, color: Palette.muted)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 9) {
                    ForEach(state.lists) { playlist in
                        PlaylistRow(playlist: playlist)
                    }
                }
                .padding(.top, 14)
            }

            PrimaryButton(title: "Create a new one", fullWidth: true, metrics: .home) {
                state.createAnother()
            }
            .padding(.top, 14)
        }
        .padding(.top, 20)
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: Radii.homePanel, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.homePanel, style: .continuous)
                        .fill(Palette.surface.opacity(0.6))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radii.homePanel, style: .continuous))
        .shadowSpec(Shadows.homePanel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("friendList")
                .ui(22, 800, color: Palette.ink)
                .tracking(-0.03 * 22)
            Spacer()
            Text("SYNCING")
                .mono(11, 400, color: Palette.faint)
                .tracking(0.06 * 11)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Playlist row

private struct PlaylistRow: View {
    let playlist: Playlist
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            StripeCover(size: 42, corner: 8, stripe: 6, period: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .ui(14, 700, color: Palette.rowName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(playlist.songCount) songs · from \(playlist.chatName)")
                    .ui(12, 400, color: Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)

            Circle()
                .fill(Palette.success)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .fill(Palette.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .strokeBorder(Color(hex: "EFEAE1"), lineWidth: 1)
        )
    }
}
