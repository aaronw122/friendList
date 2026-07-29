import XCTest
@testable import FriendList

final class PersistenceStoreTests: PersistenceTestCase {
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

    // MARK: authorization date

    func testAuthorizationDateRoundTrips() {
        XCTAssertNil(Persistence.authorizationDate)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        Persistence.authorizationDate = date

        XCTAssertEqual(Persistence.authorizationDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }
}
