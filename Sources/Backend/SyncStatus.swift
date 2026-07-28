import Foundation
import Combine

// Shared observable status both Wave-3 surfaces (the SwiftUI app and the headless entry)
// consume. UI-free on purpose: ObservableObject/@Published only, no Views. PlaylistSync
// is the sole writer; consumers observe. @MainActor so publishes land on the UI thread.
@MainActor
final class SyncStatus: ObservableObject {
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var outcomes: [SyncOutcome] = []
    @Published private(set) var needsReconnect = false
    @Published private(set) var reconnectReason: ReconnectReason?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isSyncing = false

    func begin() { isSyncing = true }

    // A run that actually executed: stamps last-synced, replaces outcomes, clears any prior error.
    func complete(outcomes: [SyncOutcome], needsReconnect: Bool, reconnectReason: ReconnectReason?) {
        isSyncing = false
        lastSyncDate = Date()
        self.outcomes = outcomes
        self.needsReconnect = needsReconnect
        self.reconnectReason = reconnectReason
        lastSyncError = nil
    }

    // A run that never got to sync (corrupt store): surface the reason, leave last-synced alone.
    func fail(_ message: String) {
        isSyncing = false
        lastSyncError = message
    }

    // The user-initiated button couldn't get the lock within its wait budget.
    func reportAlreadyRunning() {
        isSyncing = false
        lastSyncError = "Sync already running"
    }
}
