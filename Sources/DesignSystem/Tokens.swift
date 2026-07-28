import SwiftUI

// MARK: - Color hex helper

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Palette (from handoff Design Tokens)

enum Palette {
    static let accent       = Color(hex: "9B85F2")
    static let accentAlt1   = Color(hex: "B7A2FF")
    static let accentAlt2   = Color(hex: "8A6FE8")
    static let accentAlt3   = Color(hex: "7C6BD6")
    static let ink          = Color(hex: "1D1B18")
    static let body         = Color(hex: "6B6459")
    static let muted        = Color(hex: "8A8275")
    static let faint        = Color(hex: "A79E90")
    static let subheadWarm  = Color(hex: "5D574E")
    static let labelMuted   = Color(hex: "9A9184")
    static let permTitle    = Color(hex: "3A352E")
    static let permBorder   = Color(hex: "DED8CC")
    static let stepBadge    = Color(hex: "F1EDE4")
    static let line         = Color(hex: "EAE5DB")
    static let divider      = Color(hex: "F2EEE6")
    static let surface      = Color(hex: "FFFFFF")
    static let field        = Color(hex: "FDFCFA")
    static let well         = Color(hex: "F7F5F0")
    static let tint         = Color(hex: "F4F1FB")
    static let focus        = Color(hex: "B6A6F0")
    static let success      = Color(hex: "5FC559")
    static let successText  = Color(hex: "3E7A44")
    static let successBg    = Color(hex: "EFF7EF")
    static let spotify      = Color(hex: "1DB954")
    static let imessage     = Color(hex: "1B8DFF")

    static let titleBar     = Color(hex: "F3F0EA")
    static let titleText    = Color(hex: "8B8377")
    static let deskTop      = Color(hex: "FDFBF7")
    static let deskBottom   = Color(hex: "F4F0E8")

    static let privacyText  = Color(hex: "4A4459")
    static let privacyLead  = Color(hex: "2E2840")

    static let fieldInk     = Color(hex: "2A2622")
    static let rowName      = Color(hex: "2A2622")

    static let progressTrack = Color(hex: "EDE9E1")
    static let spinnerTrack  = Color(hex: "EFEBE3")

    static let deskGradient = LinearGradient(
        colors: [deskTop, deskBottom],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Radii

enum Radii {
    static let progress: CGFloat = 4
    static let chip: CGFloat = 7
    static let codeField: CGFloat = 9
    static let input: CGFloat = 10
    static let button: CGFloat = 13
    static let row: CGFloat = 12
    static let window: CGFloat = 14
    static let homePanel: CGFloat = 16
    static let sheetBottom: CGFloat = 20
    static let bubble: CGFloat = 23
    static let pill: CGFloat = 99
}

// MARK: - Window / stage geometry

enum Geometry {
    static let contentWidth: CGFloat = 760
    static let contentHeight: CGFloat = 560
    static let titleBarHeight: CGFloat = 36
    static let stageHeight: CGFloat = 524
    static let sheetWidth: CGFloat = 600
}

// MARK: - Shadows (as reusable modifiers)

struct ShadowSpec {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func shadowSpec(_ s: ShadowSpec) -> some View {
        shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

enum Shadows {
    static let window     = ShadowSpec(color: Color(hex: "282119", opacity: 0.45), radius: 35, x: 0, y: 24)
    static let sheet      = ShadowSpec(color: Color(hex: "282119", opacity: 0.40), radius: 25, x: 0, y: 20)
    static let homePanel  = ShadowSpec(color: Color(hex: "282119", opacity: 0.34), radius: 20, x: 0, y: 14)
    static let primaryBtn = ShadowSpec(color: Color(hex: "5A44BE", opacity: 0.35), radius: 9, x: 0, y: 8)
    static let spotifyBadge = ShadowSpec(color: Color(hex: "1DB954", opacity: 0.32), radius: 11, x: 0, y: 10)
    static let coverThumb = ShadowSpec(color: Color(hex: "231C14", opacity: 0.14), radius: 7, x: 0, y: 6)
}
