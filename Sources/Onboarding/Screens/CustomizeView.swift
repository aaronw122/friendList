import SwiftUI

// MARK: - Customize (step 6)

struct CustomizeView: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Palette.success)
                        .frame(width: 7, height: 7)
                    Text("\(state.found) songs found in \(state.selectedChatName)")
                        .font(UIFont2.ui(12, 700))
                        .foregroundStyle(Palette.successText)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .background(
                    RoundedRectangle(cornerRadius: Radii.pill, style: .continuous)
                        .fill(Palette.successBg)
                )

                Text("Make it yours")
                    .font(UIFont2.ui(26, 800))
                    .foregroundStyle(Palette.ink)
                    .tracking(-0.03 * 26)
                    .padding(.top, 14)

                Text("Or leave it exactly as is — it already works.")
                    .font(UIFont2.ui(14))
                    .foregroundStyle(Palette.body)
                    .padding(.top, 7)

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 10) {
                        StripeCover(size: 104)
                            .overlay(
                                Text("default\ncover")
                                    .font(UIFont2.mono(10))
                                    .foregroundStyle(Palette.faint)
                                    .multilineTextAlignment(.center)
                            )
                            .shadowSpec(Shadows.coverThumb)
                        LinkButton(title: "Use your own", size: 12) {
                            // Spotify cover upload requires a JPEG encoded to base64 at no more than 256 KB.
                        }
                    }
                    .frame(width: 104)

                    VStack(spacing: 14) {
                        LabeledField(label: "PLAYLIST NAME", text: $state.name)
                        LabeledField(label: "DESCRIPTION", text: $state.desc, fontSize: 13.5, weight: 400)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, SheetLayout.hInset)
            .padding(.top, SheetLayout.topInset)

            Spacer(minLength: 0)

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Create playlist",
                primaryEnabled: true,
                onPrimary: { state.advance() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.seedNameIfNeeded() }
    }
}
