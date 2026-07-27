import SwiftUI

// Handoff calls for Plus Jakarta Sans (UI) + IBM Plex Mono (captions/code).
// The README explicitly permits SF Pro / SF Mono substitution to stay system-native
// and to honor the "no non-Spotify network egress" privacy rule (the prototype pulled
// Google Fonts over the network, which we must NOT do). To bundle the real OFL fonts
// later: drop the .ttf files in App/Resources, register via ATSApplicationFontsPath,
// and swap the two factory functions below.

enum UIFont2 {
    /// Map handoff numeric weights (400/500/600/700/800) to SF Pro weights.
    static func weight(_ w: Int) -> Font.Weight {
        switch w {
        case ...400: return .regular
        case 401...500: return .medium
        case 501...600: return .semibold
        case 601...700: return .bold
        default: return .heavy // 800
        }
    }

    /// Primary UI face (Plus Jakarta Sans → SF Pro).
    static func ui(_ size: CGFloat, _ w: Int = 400) -> Font {
        .system(size: size, weight: weight(w), design: .default)
    }

    /// Mono face (IBM Plex Mono → SF Mono).
    static func mono(_ size: CGFloat, _ w: Int = 400) -> Font {
        .system(size: size, weight: weight(w), design: .monospaced)
    }
}

extension Text {
    /// Convenience: apply UI font + color + tracking in one call.
    func ui(_ size: CGFloat, _ w: Int = 400, color: Color = Palette.ink, tracking: CGFloat = 0) -> some View {
        self.font(UIFont2.ui(size, w)).foregroundStyle(color).tracking(tracking)
    }
    func mono(_ size: CGFloat, _ w: Int = 400, color: Color = Palette.faint, tracking: CGFloat = 0) -> some View {
        self.font(UIFont2.mono(size, w)).foregroundStyle(color).tracking(tracking)
    }
}
