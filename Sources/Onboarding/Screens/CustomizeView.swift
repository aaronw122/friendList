import SwiftUI

// MARK: - Customize (step 6)
//
// Fills from the top with a SheetFooter. Names the playlist and sets a cover
// before anything is written to Spotify.

struct CustomizeView: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Result pill (inline)
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

                // Cover (left, fixed) + fields (right, flex), 20pt gap
                HStack(alignment: .top, spacing: 20) {
                    // Cover column
                    VStack(spacing: 10) {
                        coverWell
                        LinkButton(title: state.coverPreview == nil ? "Use your own" : "Change",
                                   size: 12) {
                            state.pickCoverImage()
                        }
                        if let err = state.coverError {
                            Text(err)
                                .font(UIFont2.ui(10))
                                .foregroundStyle(Color(hex: "C2410C"))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 104)

                    // Fields column
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

    /// The chosen cover once picked, otherwise the striped default.
    @ViewBuilder
    private var coverWell: some View {
        if let cover = state.coverPreview {
            Image(nsImage: cover)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // matches StripeCover.corner
                .shadowSpec(Shadows.coverThumb)
        } else {
            StripeCover(size: 104)
                .overlay(
                    Text("default\ncover")
                        .font(UIFont2.mono(10))
                        .foregroundStyle(Palette.faint)
                        .multilineTextAlignment(.center)
                )
                .shadowSpec(Shadows.coverThumb)
        }
    }
}
