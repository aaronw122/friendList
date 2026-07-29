import Foundation
import Combine

// One headless run's result: PlaylistSync writes it; HeadlessSync reads it to decide whether to notify.
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
}
