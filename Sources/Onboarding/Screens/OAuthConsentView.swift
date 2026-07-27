import SwiftUI

// Step 5 — OAuth consent.
//
// The granted scope rows below MUST accurately mirror SpotifyConfig.scopes:
//   playlist-modify-private → "Create and edit your private playlists"
//   ugc-image-upload        → "Set your playlist's cover image"
struct OAuthConsentView: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    SpotifyMark(size: 66)

                    Text("Now the easy part")
                        .ui(26, 800, color: Palette.ink, tracking: -0.03 * 26)
                        .padding(.top, 16)

                    Text("Sign in to Spotify and give friendList permission to build playlists in your account. A browser window will open.")
                        .ui(14, 400, color: Palette.body)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    scopeCard
                        .padding(.top, 22)

                    if let err = state.connectError {
                        Text(err)
                            .ui(12.5, 400, color: Color(hex: "C2410C"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SheetLayout.hInset)
                .padding(.top, SheetLayout.topInset)
                .padding(.bottom, 8)
            }

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: state.connecting ? "Waiting for Spotify…" : "Authorize with Spotify",
                primaryEnabled: !state.connecting,
                // Real PKCE authorization via loopback (opens the browser). On a
                // successful callback connectSpotify() sets connected and advances.
                onPrimary: {
                    Task { await state.connectSpotify() }
                }
            )
        }
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScopeRow(
                dot: Palette.spotify,
                text: "Create and edit your private playlists",
                textColor: Palette.privacyText
            )
            ScopeRow(
                dot: Palette.spotify,
                text: "Set your playlist's cover image",
                textColor: Palette.privacyText
            )
            ScopeRow(
                dot: Color(hex: "D8D2C6"),
                text: "Nothing else — we never read your library, your other playlists, or your listening history",
                textColor: Palette.labelMuted
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: Radii.row, style: .continuous)
                .fill(Palette.well)
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

/// The Spotify mark: a solid green circle with three upward-bulging sound-wave
/// arcs (widest/highest at top, narrowing and descending) drawn in Spotify black.
/// Production: ship the official Spotify logo asset per their brand guidelines.
private struct SpotifyMark: View {
    var size: CGFloat = 66

    private var arcColor: Color { Color(hex: "191414") }

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2

            // (centerY factor, width factor, stroke width) — top arc is widest/highest.
            let arcs: [(cy: CGFloat, w: CGFloat, stroke: CGFloat)] = [
                (0.40, 0.60, 4.2),
                (0.52, 0.46, 3.6),
                (0.63, 0.32, 3.0),
            ]

            for arc in arcs {
                let width = arc.w * s
                let cy = arc.cy * s
                let x0 = cx - width / 2
                let x1 = cx + width / 2
                // Convex up: control point raised above the endpoints.
                let lift = 0.28 * width
                var path = Path()
                path.move(to: CGPoint(x: x0, y: cy))
                path.addQuadCurve(
                    to: CGPoint(x: x1, y: cy),
                    control: CGPoint(x: cx, y: cy - lift)
                )
                ctx.stroke(
                    path,
                    with: .color(arcColor),
                    style: StrokeStyle(lineWidth: arc.stroke, lineCap: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Palette.spotify))
        .clipShape(Circle())
        .shadowSpec(Shadows.spotifyBadge)
    }
}

/// A scope line: a 6pt dot + 12.5pt text.
private struct ScopeRow: View {
    let dot: Color
    let text: String
    let textColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 4 }
            Text(text)
                .ui(12.5, 400, color: textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
