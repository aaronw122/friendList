import XCTest
@testable import FriendList

final class PersistenceStoreTests: XCTestCase {
    private var dir: URL!
    private var legacy: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("friendlist-store-\(UUID().uuidString)", isDirectory: true)
        suiteName = "friendlist.tests.\(UUID().uuidString)"
        legacy = UserDefaults(suiteName: suiteName)
        Persistence.storeDirectoryOverride = dir
        Persistence.legacyDefaults = legacy
    }

    override func tearDown() {
        Persistence.storeDirectoryOverride = nil
        Persistence.legacyDefaults = .standard
        legacy.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: seen isolation + union

    func testSeenIsolatedBySpotifyID() {
        Persistence.recordSeen(spotifyID: "A", uris: ["spotify:track:a1"])
        Persistence.recordSeen(spotifyID: "B", uris: ["spotify:track:b1"])

        XCTAssertEqual(Persistence.seen(forSpotifyID: "A"), ["spotify:track:a1"])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "B"), ["spotify:track:b1"])
        XCTAssertTrue(Persistence.seen(forSpotifyID: "C").isEmpty)
    }

    func testRecordSeenUnionsWithoutDropping() {
        Persistence.recordSeen(spotifyID: "A", uris: ["x", "y"])
        Persistence.recordSeen(spotifyID: "A", uris: ["y", "z"])

        XCTAssertEqual(Persistence.seen(forSpotifyID: "A"), ["x", "y", "z"])
    }

    // MARK: atomic write + backup

    func testWriteKeepsBackupOfPriorGoodFile() throws {
        Persistence.recordSeen(spotifyID: "A", uris: ["first"])
        let afterFirst = try Data(contentsOf: dir.appendingPathComponent("store.json"))

        Persistence.recordSeen(spotifyID: "A", uris: ["second"])

        let backup = dir.appendingPathComponent("store.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try Data(contentsOf: backup), afterFirst)
        XCTAssertEqual(Persistence.seen(forSpotifyID: "A"), ["first", "second"])
    }

    // MARK: corrupt file never wipes seen/playlists

    func testCorruptStoreReturnsNilAndDoesNotWipe() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: dir.appendingPathComponent("store.json"))

        XCTAssertNil(Persistence.loadPlaylists())
        XCTAssertNil(Persistence.mutateStore { $0.seen["A"] = ["should-not-land"] })

        let onDisk = try Data(contentsOf: dir.appendingPathComponent("store.json"))
        XCTAssertEqual(onDisk, garbage, "corrupt store must be preserved, never overwritten with empty state")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json.corrupt").path))
    }

    // MARK: migration

    func testMigrationCopiesChatSeenToEachSpotifyIDIndependently() {
        seedLegacy(
            playlists: [
                saved(spotifyID: "S1", chatGUID: "G"),
                saved(spotifyID: "S2", chatGUID: "G"),
                saved(spotifyID: "", chatGUID: "H"),
            ],
            seen: ["G": ["u1", "u2"], "H": ["u3"]]
        )

        XCTAssertEqual(Persistence.seen(forSpotifyID: "S1"), ["u1", "u2"])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "S2"), ["u1", "u2"])
        XCTAssertEqual(Persistence.loadPlaylists()?.count, 3)

        Persistence.recordSeen(spotifyID: "S1", uris: ["u9"])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "S1"), ["u1", "u2", "u9"])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "S2"), ["u1", "u2"])
    }

    func testMigrationRunsExactlyOnce() {
        seedLegacy(playlists: [saved(spotifyID: "S1", chatGUID: "G")], seen: ["G": ["u1"]])

        XCTAssertEqual(Persistence.loadPlaylists()?.count, 1)

        seedLegacy(
            playlists: [saved(spotifyID: "S1", chatGUID: "G"), saved(spotifyID: "S2", chatGUID: "G")],
            seen: ["G": ["u1"]]
        )
        XCTAssertEqual(Persistence.loadPlaylists()?.count, 1, "store already materialized; legacy must not re-migrate")
    }

    // MARK: authorization date

    func testAuthorizationDateRoundTrips() {
        XCTAssertNil(Persistence.authorizationDate)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        Persistence.authorizationDate = date

        XCTAssertEqual(Persistence.authorizationDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: lock

    func testNonBlockingLockReentersWithinProcess() {
        let outer = Persistence.withSyncLock(blocking: false) { () -> Bool in
            Persistence.withSyncLock(blocking: false) { true } ?? false
        }
        XCTAssertEqual(outer, true)
    }

    // Holds the cross-process run lock across awaits with real thread hops (an actor hop
    // and a detached-task release), the way the sync core will — no deadlock, no unlock
    // from a non-owning context, correct data.
    func testRunLockHeldAcrossAwaitsWithThreadHops() async {
        XCTAssertTrue(Persistence.acquireSyncLock(blocking: false))

        Persistence.recordSeen(spotifyID: "A", uris: ["u1"])

        let hopper = LockHopper()
        await hopper.recordSecond()
        await Task.yield()

        await Task.detached { Persistence.releaseSyncLock() }.value

        XCTAssertEqual(Persistence.seen(forSpotifyID: "A"), ["u1", "u2"])

        XCTAssertTrue(Persistence.acquireSyncLock(blocking: false), "lock fully released and reacquirable")
        Persistence.releaseSyncLock()
    }

    // MARK: helpers

    private func saved(spotifyID: String, chatGUID: String) -> SavedPlaylist {
        SavedPlaylist(spotifyID: spotifyID, name: "n-\(spotifyID)", songCount: 0,
                      chatName: "c", chatGUID: chatGUID, externalURL: "")
    }

    private func seedLegacy(playlists: [SavedPlaylist], seen: [String: [String]]) {
        legacy.set(try! JSONEncoder().encode(playlists), forKey: "friendlist.playlists")
        legacy.set(try! JSONEncoder().encode(seen), forKey: "friendlist.seen")
    }
}

private actor LockHopper {
    func recordSecond() { Persistence.recordSeen(spotifyID: "A", uris: ["u2"]) }
}
