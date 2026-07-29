import Foundation
import UserNotifications

// Appends timestamped lines to ~/Library/Logs/friendList/sync.log (base injectable for tests),
// creating the directory on first use so a first-ever headless run never fails to log.
struct HeadlessLog {
    let directory: URL

    static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/friendList", isDirectory: true)
    }

    init(directory: URL = HeadlessLog.defaultDirectory) { self.directory = directory }

    var fileURL: URL { directory.appendingPathComponent("sync.log") }

    func append(_ message: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// One headless run's result: the per-playlist outcomes plus a non-nil message when the run
// failed or needs a Spotify reconnect (which drives the notification + persisted error).
struct HeadlessRunResult {
    let outcomes: [SyncOutcome]
    let failureMessage: String?
}

// The `--sync` executable's UI-free entry. It builds PlaylistSync from the keychain-backed
// SpotifyService (no interactive auth, no window), runs one background sync, logs it, and
// surfaces a failure via a local notification + a persisted error so a stuck sync is visible
// even if the app isn't opened for weeks.
enum HeadlessSync {
    static let syncFlag = "--sync"
    static let lastErrorKey = "friendlist.lastSyncError"

    static func isRequested(in arguments: [String]) -> Bool {
        arguments.contains(syncFlag)
    }

    // Drives the run then keeps the process alive on the main queue (so @MainActor work in
    // SyncStatus can execute) until a background waiter observes completion and exits — the
    // semaphore guarantees the process never exits mid-flight.
    static func run() -> Never {
        let log = HeadlessLog()
        log.append("headless sync starting")
        let done = DispatchSemaphore(value: 0)
        Task {
            let result = await buildAndSync(messages: MessagesReader(),
                                            spotify: SpotifyService(),
                                            persistence: AppPersistence())
            log.append(summary(result))
            if let failure = result.failureMessage {
                await notifyFailure(failure)
            }
            done.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            done.wait()
            exit(0)
        }
        dispatchMain()
    }

    // Testable core: runs the sync with injected dependencies, persists any failure, and
    // reports whether the caller should notify. Never posts notifications itself.
    @MainActor
    static func buildAndSync(messages: MessagesReading,
                             spotify: SpotifyProviding,
                             persistence: PersistenceProviding,
                             defaults: UserDefaults = .standard) async -> HeadlessRunResult {
        let status = SyncStatus()
        let sync = PlaylistSync(messages: messages, spotify: spotify, persistence: persistence, status: status)
        let outcomes = await sync.syncAll()

        let failure: String?
        if let error = status.lastSyncError {
            failure = error
        } else if status.needsReconnect {
            failure = "Reconnect Spotify to keep your playlists syncing."
        } else {
            failure = nil
        }

        if let failure {
            defaults.set(failure, forKey: lastErrorKey)
        } else {
            defaults.removeObject(forKey: lastErrorKey)
        }
        return HeadlessRunResult(outcomes: outcomes, failureMessage: failure)
    }

    static func summary(_ result: HeadlessRunResult) -> String {
        if let failure = result.failureMessage { return "sync failed: \(failure)" }
        let added = result.outcomes.reduce(0) { $0 + $1.added }
        return "sync ok: \(result.outcomes.count) playlists, \(added) tracks added"
    }

    private static func notifyFailure(_ message: String) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "FriendList sync needs attention"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
