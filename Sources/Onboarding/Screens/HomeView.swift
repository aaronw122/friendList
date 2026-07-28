import SwiftUI

struct HomeView: View {
    @Environment(OnboardingState.self) private var state
    @Environment(\.physicsBridge) private var physics
    @EnvironmentObject private var sync: SyncStatus
    @State private var banner: String?
    @State private var bannerTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            panel
                .frame(width: min(430, geo.size.width * 0.88))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 34)
        }
        .onAppear { physics.dropAll() }
        .onChange(of: sync.lastSyncDate) { _, _ in showBanner(for: sync.outcomes) }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let banner {
                BannerLine(text: banner)
                    .padding(.top, 12)
            }

            if let reconnect = reconnectPrompt {
                ReconnectPrompt(message: reconnect) { state.beginReconnect() }
                    .padding(.top, 12)
            }

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

            ForEach(attentionItems, id: \.self) { item in
                AttentionLine(text: item)
                    .padding(.top, 8)
            }

            syncBar
                .padding(.top, 14)

            PrimaryButton(title: "Create a new one", fullWidth: true, metrics: .home) {
                state.createAnother()
            }
            .padding(.top, 12)
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
            Text(sync.isSyncing ? "SYNCING" : "SYNCED")
                .mono(11, 400, color: Palette.faint)
                .tracking(0.06 * 11)
                .textCase(.uppercase)
        }
    }

    // Last-synced line paired with the user-initiated "Sync now" control.
    private var syncBar: some View {
        HStack(spacing: 10) {
            Text(statusLine)
                .ui(12, 400, color: Palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if sync.isSyncing {
                Text("Syncing…")
                    .ui(12, 600, color: Palette.faint)
            } else {
                LinkButton(title: "Sync now", size: 12.5, color: Palette.accentAlt2) {
                    state.syncNow()
                }
            }
        }
    }

    private var statusLine: String {
        if let error = sync.lastSyncError { return error }
        guard let date = sync.lastSyncDate else { return "Not synced yet" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "Last synced \(fmt.localizedString(for: date, relativeTo: Date()))"
    }

    // Hard expiry and the pre-expiry nudge share one reconnect path with distinct copy.
    private var reconnectPrompt: String? {
        if sync.needsReconnect {
            return sync.reconnectReason == .expired
                ? "Spotify access expired. Reconnect to resume syncing."
                : "Reconnect Spotify to resume syncing."
        }
        if state.reconnectNudgeActive() {
            return "Reconnect Spotify to keep syncing."
        }
        return nil
    }

    private var attentionItems: [String] {
        sync.outcomes.compactMap { outcome in
            switch outcome.skippedReason {
            case "playlist is public": return "Make “\(outcome.playlistName)” private so new songs can be added."
            case "playlist full":      return "“\(outcome.playlistName)” is full — Spotify caps playlists at 10,000 songs."
            default:                   return nil
            }
        }
    }

    private func showBanner(for outcomes: [SyncOutcome]) {
        let added = outcomes.filter { $0.added > 0 }
        guard !added.isEmpty else { return }
        let total = added.reduce(0) { $0 + $1.added }
        banner = added.count == 1
            ? "Added \(added[0].added) songs to \(added[0].playlistName)"
            : "Added \(total) songs across \(added.count) playlists"
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { banner = nil }
        }
    }
}

// MARK: - Transient banners & prompts

private struct BannerLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.success)
            Text(text)
                .ui(12.5, 600, color: Palette.successText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous).fill(Palette.successBg)
        )
        .transition(.opacity)
    }
}

private struct AttentionLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accentAlt2)
            Text(text)
                .ui(12, 500, color: Palette.body)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct ReconnectPrompt: View {
    let message: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .ui(12.5, 600, color: Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            LinkButton(title: "Reconnect", size: 12.5, color: Palette.spotify, action: action)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous).fill(Palette.tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .strokeBorder(Palette.focus.opacity(0.4), lineWidth: 1)
        )
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
                // "sent" is honest: the count is songs sent (monotonic), which can exceed the live total.
                Text("\(playlist.songCount) sent · from \(playlist.chatName)")
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
