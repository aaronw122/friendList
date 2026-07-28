import XCTest
@testable import FriendList

final class PlaylistSyncTests: PersistenceTestCase {
    // MARK: new = scanned − seen, appended and recorded

    @MainActor
    func testNewIsScannedMinusSeenAndDrivesSongCount() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.recordSeen(spotifyID: "P", uris: [uri(0)])
        let messages = MessagesFake(uris: [uri(0), uri(1), uri(2)])
        let spotify = SpotifyFake()
        let status = SyncStatus()
        let sync = PlaylistSync(messages: messages, spotify: spotify, persistence: AppPersistence(), status: status)

        let outcomes = await sync.syncAll(trigger: .background)

        // Only the two unseen URIs are appended.
        XCTAssertEqual(spotify.appended.flatMap { $0 }, [uri(1), uri(2)])
        XCTAssertEqual(outcomes, [SyncOutcome(playlistName: "P", added: 2, skippedReason: nil)])
        // songCount is derived from the seen set (all three now).
        XCTAssertEqual(Persistence.seen(forSpotifyID: "P").count, 3)
        XCTAssertEqual(Persistence.loadPlaylists()?.first?.songCount, 3)
        XCTAssertEqual(status.outcomes, outcomes)
        XCTAssertNotNil(status.lastSyncDate)
    }

    // MARK: up-to-date run is a no-op

    @MainActor
    func testUpToDateRunIsNoOp() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.recordSeen(spotifyID: "P", uris: [uri(0), uri(1)])
        let spotify = SpotifyFake()
        let sync = PlaylistSync(messages: MessagesFake(uris: [uri(0), uri(1)]),
                                spotify: spotify, persistence: AppPersistence(), status: SyncStatus())

        let outcomes = await sync.syncAll(trigger: .background)

        XCTAssertTrue(spotify.appended.isEmpty)
        XCTAssertEqual(outcomes, [SyncOutcome(playlistName: "P", added: 0, skippedReason: nil)])
    }

    // MARK: per-batch commit under a mid-run 5xx

    @MainActor
    func testMidRunFailureCommitsLandedBatchesAndReRunDoesNotDoubleAdd() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let scanned = (0..<200).map { uri($0) }
        let messages = MessagesFake(uris: scanned)

        let failing = SpotifyFake()
        failing.failAfterBatches = 1
        failing.failure = SpotifyError.http(500, "server error")
        let firstRun = PlaylistSync(messages: messages, spotify: failing,
                                    persistence: AppPersistence(), status: SyncStatus())
        let firstOutcomes = await firstRun.syncAll(trigger: .background)

        // The landed first batch is recorded; the run reports a transient skip, not reconnect.
        XCTAssertEqual(Persistence.seen(forSpotifyID: "P"), Set(scanned.prefix(100)))
        XCTAssertEqual(firstOutcomes.first?.skippedReason, "temporary error, will retry")

        let healthy = SpotifyFake()
        let secondRun = PlaylistSync(messages: messages, spotify: healthy,
                                     persistence: AppPersistence(), status: SyncStatus())
        _ = await secondRun.syncAll(trigger: .background)

        // The re-run only sends the tracks not already landed — no double-add.
        XCTAssertEqual(healthy.appended.flatMap { $0 }, Array(scanned.suffix(100)))
        XCTAssertEqual(Persistence.seen(forSpotifyID: "P"), Set(scanned))
    }

    // MARK: invalid_grant → needsReconnect(.expired), seen untouched

    @MainActor
    func testInvalidGrantMarksReconnectAndLeavesSeenUntouched() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let spotify = SpotifyFake()
        spotify.failAfterBatches = 0
        spotify.failure = SpotifyError.needsReconnect(reason: .expired)
        let status = SyncStatus()
        let sync = PlaylistSync(messages: MessagesFake(uris: [uri(0)]),
                                spotify: spotify, persistence: AppPersistence(), status: status)

        let outcomes = await sync.syncAll(trigger: .background)

        XCTAssertTrue(Persistence.seen(forSpotifyID: "P").isEmpty)
        XCTAssertEqual(outcomes.first?.skippedReason, "reconnect Spotify")
        XCTAssertTrue(status.needsReconnect)
        XCTAssertEqual(status.reconnectReason, .expired)
    }

    // MARK: transient 5xx → skip without reconnect

    @MainActor
    func testTransientFailureSkipsWithoutReconnect() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let spotify = SpotifyFake()
        spotify.failAfterBatches = 0
        spotify.failure = SpotifyError.http(503, "unavailable")
        let status = SyncStatus()
        let sync = PlaylistSync(messages: MessagesFake(uris: [uri(0)]),
                                spotify: spotify, persistence: AppPersistence(), status: status)

        let outcomes = await sync.syncAll(trigger: .background)

        XCTAssertEqual(outcomes.first?.skippedReason, "temporary error, will retry")
        XCTAssertFalse(status.needsReconnect)
    }

    // MARK: 403 public / full → distinct skipped outcomes

    @MainActor
    func testPublicAndFullPlaylistsYieldDistinctSkips() async {
        for (failure, reason) in [(SpotifyError.playlistPublic, "playlist is public"),
                                  (SpotifyError.playlistFull, "playlist full")] {
            Persistence.storeDirectoryOverride = dir.appendingPathComponent(reason, isDirectory: true)
            seedPlaylist(spotifyID: "P", chatGUID: "G")
            let spotify = SpotifyFake()
            spotify.failAfterBatches = 0
            spotify.failure = failure
            let sync = PlaylistSync(messages: MessagesFake(uris: [uri(0)]),
                                    spotify: spotify, persistence: AppPersistence(), status: SyncStatus())

            let outcomes = await sync.syncAll(trigger: .background)
            XCTAssertEqual(outcomes.first?.skippedReason, reason)
        }
    }

    // MARK: no disk access → skipped

    @MainActor
    func testNoDiskAccessSkips() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        let sync = PlaylistSync(messages: MessagesFake(uris: [uri(0)], readable: false),
                                spotify: SpotifyFake(), persistence: AppPersistence(), status: SyncStatus())

        let outcomes = await sync.syncAll(trigger: .background)
        XCTAssertEqual(outcomes.first?.skippedReason, "no Full Disk Access")
    }

    // MARK: non-blocking acquire returns immediately when the lock is held elsewhere

    @MainActor
    func testBackgroundSkipsImmediatelyWhenLockBusy() async {
        let messages = MessagesFake(uris: [uri(0)])
        let spotify = SpotifyFake()
        let sync = PlaylistSync(messages: messages, spotify: spotify,
                                persistence: BusyPersistence(), status: SyncStatus())

        let outcomes = await sync.syncAll(trigger: .background)

        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertFalse(messages.canReadCalled, "must not touch the chat when it can't get the lock")
        XCTAssertTrue(spotify.appended.isEmpty)
    }

    // MARK: bounded-blocking acquire gives up and reports already-running

    @MainActor
    func testUserInitiatedReportsAlreadyRunningWhenLockNeverFrees() async {
        let status = SyncStatus()
        var sync = PlaylistSync(messages: MessagesFake(uris: [uri(0)]), spotify: SpotifyFake(),
                                persistence: BusyPersistence(), status: status)
        sync.busyWait = 0.15
        sync.busyPoll = 0.05

        let outcomes = await sync.syncAll(trigger: .userInitiated)

        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertEqual(status.lastSyncError, "Sync already running")
    }

    // MARK: helpers

    private func uri(_ i: Int) -> String { "spotify:track:\(i)" }

    private func seedPlaylist(spotifyID: String, chatGUID: String) {
        Persistence.upsertPlaylists([SavedPlaylist(spotifyID: spotifyID, name: spotifyID, songCount: 0,
                                                   chatName: "chat", chatGUID: chatGUID, externalURL: "")])
    }
}

// MARK: - Fakes (MessagesFake / SpotifyFake are shared — see TestSupport.swift)

// Always refuses the lock, so the run can't acquire it — simulates another active process.
private struct BusyPersistence: PersistenceProviding {
    var didOnboard = false
    var authorizationDate: Date?
    func loadPlaylists() -> [SavedPlaylist]? { [] }
    func upsertPlaylists(_ updates: [SavedPlaylist]) {}
    func recordSeen(spotifyID: String, uris: [String]) {}
    func seen(forSpotifyID id: String) -> Set<String> { [] }
    func acquireSyncLock(blocking: Bool) -> Bool { false }
    func releaseSyncLock() {}
}
