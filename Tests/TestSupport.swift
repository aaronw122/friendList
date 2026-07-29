import XCTest
@testable import FriendList

// Shared test scaffolding for the auto-sync suite: one temp-store base case and one fake per
// backend seam, so the five suites don't each re-declare their own.

// MARK: - Temp-store base case

/// Points `Persistence` at a throwaway store directory for the duration of a test, and cleans it
/// up afterward. Subclasses that need extra setup override and call super.
class PersistenceTestCase: XCTestCase {
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("friendlist-\(UUID().uuidString)", isDirectory: true)
        Persistence.storeDirectoryOverride = dir
    }

    override func tearDown() {
        Persistence.storeDirectoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }
}

// MARK: - Messages seam fake

/// Thread-safe call log so a value-type `MessagesFake` can record reads seen through any of its copies.
final class MessagesReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var canReadHits = 0
    private var scanHits = 0
    func markCanRead() { lock.lock(); canReadHits += 1; lock.unlock() }
    func markScan() { lock.lock(); scanHits += 1; lock.unlock() }
    var canReadCount: Int { lock.lock(); defer { lock.unlock() }; return canReadHits }
    var scanCount: Int { lock.lock(); defer { lock.unlock() }; return scanHits }
}

struct MessagesFake: MessagesReading {
    var uris: [String] = []
    var readable = true
    private let log = MessagesReadLog()

    /// True once `canRead()` has run — lets a test assert the chat was (not) touched.
    var canReadCalled: Bool { log.canReadCount > 0 }
    /// How many times a run actually scanned — proves whether a second run fired.
    var scanCount: Int { log.scanCount }

    func canRead() -> Bool { log.markCanRead(); return readable }
    func groupChats() throws -> [GroupChat] { [] }
    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        log.markScan()
        return ChatScan(trackURIs: uris, youtubeCount: 0, messagesScanned: uris.count)
    }
}

// MARK: - Spotify seam fake

/// One configurable Spotify double for every suite: records create/append calls and can inject a
/// restore/create failure or an append failure after N landed batches.
final class SpotifyFake: SpotifyProviding, @unchecked Sendable {
    struct CreateRequest: Equatable {
        let name: String
        let description: String
        let uris: [String]
    }

    var savedID: String?
    var restored: SpotifySession?
    var restoreError: Error?
    var createError: Error?
    /// Throw `failure` once this many batches have landed (0 = before the first batch). nil never throws.
    var failAfterBatches: Int?
    var failure: Error = SpotifyError.http(500, "server error")

    private let lock = NSLock()
    private var appendedBatches: [[String]] = []
    private var createRequest: CreateRequest?

    var appended: [[String]] { lock.lock(); defer { lock.unlock() }; return appendedBatches }
    var lastCreateRequest: CreateRequest? { lock.lock(); defer { lock.unlock() }; return createRequest }

    init(savedID: String? = nil,
         restored: SpotifySession? = nil,
         restoreError: Error? = nil,
         createError: Error? = nil) {
        self.savedID = savedID
        self.restored = restored
        self.restoreError = restoreError
        self.createError = createError
    }

    func savedClientID() async -> String? { savedID }

    func restoreSession() async throws -> SpotifySession? {
        if let restoreError { throw restoreError }
        return restored
    }

    func connect(clientID: String) async throws -> String { "Connected User" }

    func createPlaylist(name: String, description: String, trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        lock.lock(); createRequest = CreateRequest(name: name, description: description, uris: trackURIs); lock.unlock()
        if let createError { throw createError }
        progress(1, "Done")
        return SpotifyPlaylistResult(id: "playlist-id", url: "https://open.spotify.com/playlist/id", added: trackURIs.count)
    }

    func appendTracks(playlistID: String, trackURIs: [String], onBatchAdded: ([String]) -> Void) async throws -> Int {
        var added = 0
        var landed = 0
        for batch in trackURIs.chunked(100) {
            if let cap = failAfterBatches, landed >= cap { throw failure }
            onBatchAdded(batch)
            lock.lock(); appendedBatches.append(batch); lock.unlock()
            added += batch.count
            landed += 1
        }
        return added
    }
}
