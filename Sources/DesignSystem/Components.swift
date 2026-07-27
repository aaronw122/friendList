import SwiftUI

// MARK: - Primary CTA

/// Metrics for the accent button. Default = the "Continue" CTA (15/700, 14×44, r13).
struct ButtonMetrics {
    var fontSize: CGFloat = 15
    var fontWeight: Int = 700
    var vPad: CGFloat = 14
    var hPad: CGFloat = 44
    var radius: CGFloat = Radii.button
    var shadow: ShadowSpec = Shadows.primaryBtn
    var hoverRadius: CGFloat = 12
    var hoverY: CGFloat = 11

    static let cta = ButtonMetrics()
    /// "Grant access" — 14/700, 11×24, r11, shadow 0 6px 14px rgba(90,68,190,.30).
    static let compact = ButtonMetrics(
        fontSize: 14, vPad: 11, hPad: 24, radius: 11,
        shadow: ShadowSpec(color: Color(hex: "5A44BE", opacity: 0.30), radius: 7, x: 0, y: 6),
        hoverRadius: 9, hoverY: 8)
    /// Home "Create a new one" — 14/700, pad 12, r12, shadow 0 7px 16px rgba(90,68,190,.30).
    static let home = ButtonMetrics(
        fontSize: 14, vPad: 12, hPad: 0, radius: 12,
        shadow: ShadowSpec(color: Color(hex: "5A44BE", opacity: 0.30), radius: 8, x: 0, y: 7),
        hoverRadius: 10, hoverY: 9)
}

/// Accent CTA: white on accent, drop shadow + inner top highlight + inner bottom
/// shade. Hover lifts 2pt, active presses 1pt. Pass `metrics:` for the variants.
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var fullWidth: Bool = false
    var metrics: ButtonMetrics = .cta
    let action: () -> Void

    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(UIFont2.ui(metrics.fontSize, metrics.fontWeight))
                .foregroundStyle(.white)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, metrics.vPad)
                .padding(.horizontal, fullWidth ? 0 : metrics.hPad)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                        .fill(enabled ? Palette.accent : Palette.permBorder)
                )
                .overlay(
                    // inner top highlight + inner bottom shade approximation
                    RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(enabled ? 0.35 : 0),
                                         Color.clear,
                                         Color.black.opacity(enabled ? 0.12 : 0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .shadow(color: enabled ? metrics.shadow.color : .clear,
                radius: enabled ? (hovering ? metrics.hoverRadius : metrics.shadow.radius) : 0,
                x: 0, y: enabled ? (hovering ? metrics.hoverY : metrics.shadow.y) : 0)
        .offset(y: pressing ? 1 : (hovering && enabled ? -2 : 0))
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.08), value: pressing)
        .onHover { hovering = $0 }
        .pointerStyle(enabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
    }
}

private extension View {
    @ViewBuilder func pointerStyle(_ enabled: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(enabled ? .link : .default)
        } else { self }
    }
}

// MARK: - Plain underlined link (Back / secondary actions)

struct LinkButton: View {
    let title: String
    var size: CGFloat = 13
    var color: Color = Palette.body
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIFont2.ui(size, 500))
                .foregroundStyle(color)
                .underline(true, color: color.opacity(hovering ? 0.85 : 0.55)) // plain underlined link
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Sheet top progress bar

/// 4pt strip pinned to the top of the sheet. Widths by step (2→16% … 8→100%).
struct SheetTopProgressBar: View {
    let fraction: Double // 0...1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.progressTrack)
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: max(0, geo.size.width * fraction))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .animation(.easeInOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Labeled text field (Customize / Spotify inputs)

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var fontSize: CGFloat = 14
    var weight: Int = 600          // input text weight (Name = 600; Description = 400)
    var labelColor: Color = Palette.labelMuted

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(UIFont2.ui(11.5, 700))
                    .tracking(0.06 * 11.5)
                    .foregroundStyle(labelColor)
                    .textCase(.uppercase)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(mono ? UIFont2.mono(fontSize) : UIFont2.ui(fontSize, weight))
                .foregroundStyle(Palette.fieldInk)
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                .background(
                    RoundedRectangle(cornerRadius: Radii.input, style: .continuous)
                        .fill(Palette.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.input, style: .continuous)
                        .strokeBorder(focused ? Palette.focus : Palette.line, lineWidth: 1.5)
                )
                .focused($focused)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}

// MARK: - Persistent privacy footer ("On device · nothing leaves your Mac")

/// PLAN requires a persistent local-only reassurance affordance on every screen.
struct PrivacyFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("On device · nothing leaves your Mac")
                .font(UIFont2.mono(10.5))
                .tracking(0.02 * 10.5)
        }
        .foregroundStyle(Palette.faint)
    }
}

// MARK: - Sheet layout helpers

enum SheetLayout {
    /// Sheet content padding (sheet is 600pt wide) — matches the HTML prototype.
    static let hInset: CGFloat = 34
    static let topInset: CGFloat = 26
    static let footerInset: CGFloat = 24
}

/// Standard footer row for sheet screens: a plain "Back" link on the left,
/// a primary CTA on the right. Either side may be omitted.
struct SheetFooter: View {
    var backTitle: String? = "Back"
    var onBack: (() -> Void)? = nil
    var primaryTitle: String? = nil
    var primaryEnabled: Bool = true
    var onPrimary: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let backTitle, let onBack {
                LinkButton(title: backTitle, size: 13, color: Palette.body, action: onBack)
            }
            Spacer()
            if let primaryTitle, let onPrimary {
                PrimaryButton(title: primaryTitle, enabled: primaryEnabled, action: onPrimary)
            }
        }
        .padding(.horizontal, SheetLayout.hInset)
        .padding(.vertical, SheetLayout.footerInset)
    }
}

// MARK: - Striped cover placeholder (default playlist cover)

/// Diagonal stripe pattern (default playlist cover) #EFEBE3 / #E6E1D8 at 135°.
/// Cover well: stripe 8 / period 16. Home & AllSet thumbs: stripe 6 / period 12.
struct StripeCover: View {
    var size: CGFloat = 104
    var corner: CGFloat = 10
    var stripe: CGFloat = 8
    var period: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(Color(hex: "EFEBE3")))
            ctx.rotate(by: .degrees(135))
            let diag = (sz.width + sz.height) * 2
            var x: CGFloat = -diag
            while x < diag {
                let bar = CGRect(x: x, y: -diag, width: stripe, height: diag * 2)
                ctx.fill(Path(bar), with: .color(Color(hex: "E6E1D8")))
                x += period
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
