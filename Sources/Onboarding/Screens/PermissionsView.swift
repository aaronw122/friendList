import SwiftUI

/// Step 2 — Permissions. "Some quick housekeeping": requests Full Disk Access,
/// with the local-only privacy reassurance below the button. Continue unlocks
/// once access is granted; the CTA stays in place and enables in situ.
struct PermissionsView: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("Some quick housekeeping")
                    .font(UIFont2.ui(26, 800))
                    .tracking(-0.03 * 26)
                    .foregroundStyle(Palette.ink)

                accessCard
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetLayout.hInset)

            Spacer(minLength: 0)

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Continue",
                primaryEnabled: state.access,
                onPrimary: { state.advance() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.probeAccessOnAppear() }
        .onDisappear { state.cancelAccessPolling() }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.access {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.success)
                    Text("Full Disk Access granted")
                        .font(UIFont2.ui(15, 700))
                        .foregroundStyle(Palette.ink)
                }
            } else {
                Text("friendList needs Full Disk Access to read Messages")
                    .font(UIFont2.ui(18, 700))
                    .foregroundStyle(Palette.permTitle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("this opens System Settings — you'll need to toggle friendList on")
                    .font(UIFont2.ui(12.5))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                PrimaryButton(title: "Request access", metrics: .compact) { state.requestAccess() }
                    .padding(.top, 16)
            }

            privacyText
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
    }

    private var privacyText: some View {
        VStack(alignment: .leading, spacing: 8) {
            (
                Text("Your chats stay private. ")
                    .font(UIFont2.ui(12.5, 700))
                    .foregroundStyle(Palette.privacyLead)
                + Text("friendList scans Messages locally to find song links.")
                    .font(UIFont2.ui(12.5))
                    .foregroundStyle(Palette.privacyText)
            )
            .lineSpacing(6)
            .multilineTextAlignment(.leading)

            Link(destination: URL(string: "https://github.com/aaronw122/friendList")!) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("View the source on GitHub")
                        .font(UIFont2.ui(12, 700))
                }
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F0EADD"))
        )
    }
}
