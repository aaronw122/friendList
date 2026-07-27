import Foundation
import AppKit

/// Full Disk Access is required to read `~/Library/Messages/chat.db`. macOS gives
/// no API to *grant* it and no reliable API to query it — the only honest probe
/// is to try a read. The user toggles the app in System Settings; a non-sandboxed
/// app usually gains access while running, but macOS may require a relaunch, so we
/// persist a resume marker (see `Persistence.resumeAtPicker`) and re-probe on launch.
enum FullDiskAccess {
    /// Legacy anchor (pre-Ventura). On macOS 13+ it may just open the Privacy root;
    /// that's acceptable — we also show on-screen instructions as the real fallback.
    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openSettings() {
        if !NSWorkspace.shared.open(settingsURL) {
            // Fallback: open System Settings at all.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }

    /// True when chat.db is actually readable.
    static func isGranted(reader: MessagesReading = MessagesReader()) -> Bool {
        reader.canRead()
    }
}
