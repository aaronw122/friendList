import Foundation
import AppKit

/// macOS exposes no reliable FDA status API; probe chat.db and persist a relaunch-resume marker.
enum FullDiskAccess {
    /// This pre-Ventura anchor may open only the Privacy root on macOS 13+, so the UI also shows instructions.
    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openSettings() {
        if !NSWorkspace.shared.open(settingsURL) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }

    static func isGranted(reader: MessagesReading = MessagesReader()) -> Bool {
        reader.canRead()
    }
}
