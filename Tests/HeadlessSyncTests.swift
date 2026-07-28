import XCTest
@testable import FriendList

final class HeadlessSyncTests: XCTestCase {
    private var dir: URL!
    private var legacy: UserDefaults!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("friendlist-headless-\(UUID().uuidString)", isDirectory: true)
        suiteName = "friendlist.headless.\(UUID().uuidString)"
        legacy = UserDefaults(suiteName: suiteName)
        defaults = UserDefaults(suiteName: "\(suiteName).store")
        Persistence.storeDirectoryOverride = dir
        Persistence.legacyDefaults = legacy
    }

    override func tearDown() {
        Persistence.storeDirectoryOverride = nil
        Persistence.legacyDefaults = .standard
        legacy.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: "\(suiteName).store")
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: arg parsing

    func testSyncFlagDetection() {
        XCTAssertTrue(HeadlessSync.isRequested(in: ["/path/FriendList", "--sync"]))
        XCTAssertFalse(HeadlessSync.isRequested(in: ["/path/FriendList"]))
    }

    // MARK: --sync dependency-building path with fakes

    @MainActor
    func testBuildAndSyncAppendsAndReportsHealthy() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let spotify = SpotifyStub()
        let result = await HeadlessSync.buildAndSync(messages: MessagesStub(uris: [uri(0), uri(1)]),
                                                     spotify: spotify,
                                                     persistence: AppPersistence(),
                                                     defaults: defaults)

        XCTAssertEqual(result.outcomes, [SyncOutcome(playlistName: "P", added: 2, skippedReason: nil)])
        XCTAssertNil(result.failureMessage)
        XCTAssertNil(defaults.string(forKey: HeadlessSync.lastErrorKey))
        XCTAssertEqual(HeadlessSync.summary(result), "sync ok: 1 playlists, 2 tracks added")
    }

    @MainActor
    func testBuildAndSyncPersistsReconnectFailure() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let spotify = SpotifyStub()
        spotify.failure = SpotifyError.needsReconnect(reason: .expired)
        let result = await HeadlessSync.buildAndSync(messages: MessagesStub(uris: [uri(0)]),
                                                     spotify: spotify,
                                                     persistence: AppPersistence(),
                                                     defaults: defaults)

        XCTAssertNotNil(result.failureMessage)
        XCTAssertEqual(defaults.string(forKey: HeadlessSync.lastErrorKey), result.failureMessage)
        XCTAssertTrue(HeadlessSync.summary(result).hasPrefix("sync failed:"))
    }

    // MARK: log-dir creation

    func testLogCreatesDirectoryAndAppends() {
        let logDir = dir.appendingPathComponent("Logs/friendList", isDirectory: true)
        let log = HeadlessLog(directory: logDir)
        log.append("first")
        log.append("second")

        XCTAssertTrue(FileManager.default.fileExists(atPath: logDir.path))
        let contents = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(contents.contains("first"))
        XCTAssertTrue(contents.contains("second"))
    }

    // MARK: registration helper (plist name + agent construction; no live register())

    func testBackgroundAgentPlistNameAndService() {
        XCTAssertEqual(BackgroundSyncAgent.label, "com.friendlist.app.sync")
        XCTAssertEqual(BackgroundSyncAgent.plistName, "com.friendlist.app.sync.plist")
        XCTAssertNotNil(BackgroundSyncAgent.service())
    }

    // MARK: helpers

    private func uri(_ i: Int) -> String { "spotify:track:\(i)" }

    private func seedPlaylist(spotifyID: String, chatGUID: String) {
        Persistence.upsertPlaylists([SavedPlaylist(spotifyID: spotifyID, name: spotifyID, songCount: 0,
                                                   chatName: "chat", chatGUID: chatGUID, externalURL: "")])
    }
}

// MARK: - Fakes

private struct MessagesStub: MessagesReading {
    var uris: [String]
    func canRead() -> Bool { true }
    func groupChats() throws -> [GroupChat] { [] }
    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        ChatScan(trackURIs: uris, youtubeCount: 0, messagesScanned: uris.count)
    }
}

private final class SpotifyStub: SpotifyProviding, @unchecked Sendable {
    var failure: Error?

    func savedClientID() async -> String? { nil }
    func restoreSession() async throws -> SpotifySession? { nil }
    func connect(clientID: String) async throws -> String { "" }
    func createPlaylist(name: String, description: String, trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        SpotifyPlaylistResult(id: "id", url: "", added: trackURIs.count)
    }
    func appendTracks(playlistID: String, trackURIs: [String], onBatchAdded: ([String]) -> Void) async throws -> Int {
        if let failure { throw failure }
        for batch in trackURIs.chunked(100) { onBatchAdded(batch) }
        return trackURIs.count
    }
}
