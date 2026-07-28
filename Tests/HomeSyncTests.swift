import XCTest
@testable import FriendList

@MainActor
final class HomeSyncTests: XCTestCase {
    private var dir: URL!
    private var legacy: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("friendlist-home-\(UUID().uuidString)", isDirectory: true)
        suiteName = "friendlist.hometests.\(UUID().uuidString)"
        legacy = UserDefaults(suiteName: suiteName)
        Persistence.storeDirectoryOverride = dir
        Persistence.legacyDefaults = legacy
        Persistence.didOnboard = false
    }

    override func tearDown() {
        Persistence.storeDirectoryOverride = nil
        Persistence.legacyDefaults = .standard
        Persistence.didOnboard = false
        legacy.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: startLaunchSyncIfOnboarded gating

    func testLaunchSyncRunsWhenOnboardedWithPlaylists() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = true
        let spotify = AppendRecordingSpotify()
        let state = makeState(messages: MessagesFake(uris: [uri(0), uri(1)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await waitUntil { state.syncStatus.lastSyncDate != nil }

        let appended = await spotify.appended
        XCTAssertEqual(appended.flatMap { $0 }, [uri(0), uri(1)])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "P").count, 2)
        // Home counts refreshed in place from the store.
        XCTAssertEqual(state.lists.first?.songCount, 2)
    }

    func testLaunchSyncNoOpWhenNotOnboarded() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = false
        let spotify = AppendRecordingSpotify()
        let state = makeState(messages: MessagesFake(uris: [uri(0)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await settle()

        let appended = await spotify.appended
        XCTAssertNil(state.syncStatus.lastSyncDate)
        XCTAssertTrue(appended.isEmpty)
    }

    func testLaunchSyncNoOpWhenNoPlaylists() async {
        Persistence.didOnboard = true
        let spotify = AppendRecordingSpotify()
        let state = makeState(messages: MessagesFake(uris: [uri(0)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await settle()

        let appended = await spotify.appended
        XCTAssertTrue(state.lists.isEmpty)
        XCTAssertNil(state.syncStatus.lastSyncDate)
        XCTAssertTrue(appended.isEmpty)
    }

    func testLaunchSyncRunsOnlyOncePerLaunch() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = true
        let spotify = AppendRecordingSpotify()
        let state = makeState(messages: MessagesFake(uris: [uri(0)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await waitUntil { state.syncStatus.lastSyncDate != nil }
        state.startLaunchSyncIfOnboarded()  // guarded: must not fire a second run
        await settle()

        let appended = await spotify.appended
        XCTAssertEqual(appended.count, 1)
    }

    // MARK: pre-expiry reconnect nudge threshold

    func testReconnectNudgeFiresInsideTwoWeekWindowOnly() {
        let state = makeState(messages: MessagesFake(uris: []), spotify: AppendRecordingSpotify())
        let cal = Calendar.current
        let authorized = Date(timeIntervalSince1970: 1_700_000_000)
        state.persistence.authorizationDate = authorized
        let anniversary = cal.date(byAdding: .month, value: 6, to: authorized)!

        let inside = cal.date(byAdding: .day, value: -7, to: anniversary)!
        let before = cal.date(byAdding: .day, value: -30, to: anniversary)!
        let after = cal.date(byAdding: .day, value: 1, to: anniversary)!

        XCTAssertTrue(state.reconnectNudgeActive(now: inside))
        XCTAssertFalse(state.reconnectNudgeActive(now: before))
        XCTAssertFalse(state.reconnectNudgeActive(now: after), "past the anniversary is the hard expired state, not the nudge")
    }

    func testReconnectNudgeInactiveWithoutAuthorizationDate() {
        let state = makeState(messages: MessagesFake(uris: []), spotify: AppendRecordingSpotify())
        state.persistence.authorizationDate = nil
        XCTAssertFalse(state.reconnectNudgeActive(now: Date()))
    }

    // MARK: helpers

    private func uri(_ i: Int) -> String { "spotify:track:\(i)" }

    private func seedPlaylist(spotifyID: String, chatGUID: String) {
        Persistence.upsertPlaylists([SavedPlaylist(spotifyID: spotifyID, name: spotifyID, songCount: 0,
                                                   chatName: "chat", chatGUID: chatGUID, externalURL: "")])
    }

    private func makeState(messages: MessagesReading, spotify: SpotifyProviding) -> OnboardingState {
        OnboardingState(messages: messages, spotify: spotify, persistence: AppPersistence())
    }

    private func waitUntil(timeout: TimeInterval = 2, _ cond: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // Give any detached no-op path a beat to prove it did NOT start a run.
    private func settle() async { try? await Task.sleep(nanoseconds: 300_000_000) }
}

// MARK: - Fakes

private struct MessagesFake: MessagesReading {
    var uris: [String]
    func canRead() -> Bool { true }
    func groupChats() throws -> [GroupChat] { [] }
    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        ChatScan(trackURIs: uris, youtubeCount: 0, messagesScanned: uris.count)
    }
}

private actor AppendRecordingSpotify: SpotifyProviding {
    private(set) var appended: [[String]] = []
    func savedClientID() -> String? { nil }
    func restoreSession() throws -> SpotifySession? { nil }
    func connect(clientID: String) async throws -> String { "" }
    func createPlaylist(name: String, description: String, trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        SpotifyPlaylistResult(id: "id", url: "", added: trackURIs.count)
    }
    func appendTracks(playlistID: String, trackURIs: [String], onBatchAdded: ([String]) -> Void) async throws -> Int {
        for batch in trackURIs.chunked(100) {
            onBatchAdded(batch)
            appended.append(batch)
        }
        return trackURIs.count
    }
}
