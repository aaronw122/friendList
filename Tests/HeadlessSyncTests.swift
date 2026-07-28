import XCTest
@testable import FriendList

final class HeadlessSyncTests: PersistenceTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "\(suiteName!).store")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "\(suiteName!).store")
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
        let spotify = SpotifyFake()
        let result = await HeadlessSync.buildAndSync(messages: MessagesFake(uris: [uri(0), uri(1)]),
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
        let spotify = SpotifyFake()
        spotify.failAfterBatches = 0
        spotify.failure = SpotifyError.needsReconnect(reason: .expired)
        let result = await HeadlessSync.buildAndSync(messages: MessagesFake(uris: [uri(0)]),
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

    // MARK: helpers

    private func uri(_ i: Int) -> String { "spotify:track:\(i)" }

    private func seedPlaylist(spotifyID: String, chatGUID: String) {
        Persistence.upsertPlaylists([SavedPlaylist(spotifyID: spotifyID, name: spotifyID, songCount: 0,
                                                   chatName: "chat", chatGUID: chatGUID, externalURL: "")])
    }
}
