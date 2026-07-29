import Foundation
import Combine

@MainActor
final class SyncStatus: ObservableObject {
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var outcomes: [SyncOutcome] = []
    @Published private(set) var needsReconnect = false
    @Published private(set) var reconnectReason: ReconnectReason?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isSyncing = false

    func begin() { isSyncing = true }

    func complete(outcomes: [SyncOutcome], needsReconnect: Bool, reconnectReason: ReconnectReason?) {
        isSyncing = false
        lastSyncDate = Date()
        self.outcomes = outcomes
        self.needsReconnect = needsReconnect
        self.reconnectReason = reconnectReason
        lastSyncError = nil
    }

    func fail(_ message: String) {
        isSyncing = false
        lastSyncError = message
    }
}
