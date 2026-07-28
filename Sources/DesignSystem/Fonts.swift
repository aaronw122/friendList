import SwiftUI

// Use system fonts to avoid non-Spotify network egress; bundled OFL fonts can replace them later.

enum UIFont2 {
    static func weight(_ w: Int) -> Font.Weight {
        switch w {
        case ...400: return .regular
        case 401...500: return .medium
        case 501...600: return .semibold
        case 601...700: return .bold
        default: return .heavy
        }
    }

    static func ui(_ size: CGFloat, _ w: Int = 400) -> Font {
        .system(size: size, weight: weight(w), design: .default)
    }

    static func mono(_ size: CGFloat, _ w: Int = 400) -> Font {
        .system(size: size, weight: weight(w), design: .monospaced)
    }
}

extension Text {
    func ui(_ size: CGFloat, _ w: Int = 400, color: Color = Palette.ink, tracking: CGFloat = 0) -> some View {
        self.font(UIFont2.ui(size, w)).foregroundStyle(color).tracking(tracking)
    }
    func mono(_ size: CGFloat, _ w: Int = 400, color: Color = Palette.faint, tracking: CGFloat = 0) -> some View {
        self.font(UIFont2.mono(size, w)).foregroundStyle(color).tracking(tracking)
    }
}
