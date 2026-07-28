import SwiftUI

// Native apps cannot keep a client secret, so Spotify authorization uses only a client ID with PKCE.
struct SpotifyKeysView: View {
    @Environment(OnboardingState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sorry — Spotify makes us do this")
                        .ui(26, 800, color: Palette.ink, tracking: -0.03 * 26)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("We need you to create a key yourself. It should take less than 2 minutes.")
                        .ui(14, 400, color: Palette.body)
                        .lineSpacing(7)
                        .frame(maxWidth: 470, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 16) {
                        stepLogin
                        stepDashboard
                        stepForm
                        stepClientId(clientId: $state.clientId)
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, SheetLayout.hInset)
                .padding(.top, SheetLayout.topInset)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Connect Spotify",
                primaryEnabled: !state.clientId.trimmingCharacters(in: .whitespaces).isEmpty,
                onPrimary: { state.advance() }
            )
        }
    }

    // MARK: Steps

    private var stepLogin: some View {
        StepRow(number: 1) {
            Text("Log in to Spotify.")
                .ui(15.5, 700, color: Palette.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            LaunchButton(title: "Log in to Spotify", systemImage: "person.crop.circle") {
                openURL(SpotifyConfig.loginURL)
            }
            .padding(.top, 2)

            Text("Opens Spotify's login in your browser. Already logged in? You'll breeze right past it.")
                .ui(12.5, 400, color: Palette.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepDashboard: some View {
        StepRow(number: 2) {
            Text("Open the developer dashboard and click **Create app**.")
                .ui(15.5, 700, color: Palette.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            LaunchButton(title: "Open Spotify Dashboard", systemImage: "arrow.up.forward.square") {
                openURL(SpotifyConfig.dashboardURL)
            }
            .padding(.top, 2)

            Text("Now that you're signed in, this lands on your dashboard. Accept the Developer Terms if it asks.")
                .ui(12.5, 400, color: Palette.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepForm: some View {
        StepRow(number: 3) {
            Text("Fill in the form with these exact values:")
                .ui(15.5, 700, color: Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                KeyValueRow(label: "App name", value: SpotifyConfig.appName)
                KeyValueRow(label: "App description", value: SpotifyConfig.appDescription)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Redirect URI")
                        .ui(12.5, 400, color: Palette.muted)
                    RedirectURIField()
                    Text("must be exact.")
                        .ui(12, 400, color: Palette.faint)
                }

                KeyValueRow(label: "Which API/SDKs?", value: "✅ Web API")
            }
            .padding(.top, 2)

            Text("Tick the Terms box, then Save.")
                .ui(12.5, 400, color: Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepClientId(clientId: Binding<String>) -> some View {
        StepRow(number: 4) {
            Text("Open your new app's **Settings**, copy the **Client ID**, and paste it here:")
                .ui(15.5, 700, color: Palette.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "CLIENT ID", text: clientId, placeholder: "Client ID", mono: true)
                .padding(.top, 2)

            HStack(alignment: .top, spacing: 5) {
                Text("🔒")
                    .font(.system(size: 11))
                Text("This key lives only on this Mac. friendList has no server — your Client ID never leaves your computer.")
                    .ui(12, 400, color: Palette.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Step scaffold

private struct StepRow<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(UIFont2.ui(12, 700))
                .foregroundStyle(Palette.body)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.stepBadge)
                )

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Pieces

private struct LaunchButton: View {
    let title: String
    var systemImage: String = "arrow.up.forward.square"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(UIFont2.ui(12.5, 700))
            }
            .foregroundStyle(Palette.body)
            .padding(.vertical, 7)
            .padding(.horizontal, 13)
            .background(
                RoundedRectangle(cornerRadius: Radii.chip, style: .continuous)
                    .fill(hovering ? Palette.line : Palette.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radii.chip, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .ui(12.5, 400, color: Palette.muted)
            Spacer(minLength: 12)
            Text(value)
                .mono(12.5, 400, color: Palette.fieldInk)
        }
    }
}

private struct RedirectURIField: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Text(SpotifyConfig.redirectURI)
                .mono(12.5, 400, color: Palette.fieldInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(copied: state.copied, action: copy)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Radii.codeField, style: .continuous)
                .fill(Palette.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radii.codeField, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SpotifyConfig.redirectURI, forType: .string)
        state.copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            state.copied = false
        }
    }
}

private struct CopyButton: View {
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(copied ? "Copied" : "Copy")
                .font(UIFont2.ui(11.5, 700))
                .foregroundStyle(Palette.subheadWarm)
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: "E9E4DA").opacity(hovering ? 0.75 : 1))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
