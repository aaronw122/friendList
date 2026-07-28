import XCTest
@testable import FriendList

@MainActor
final class HomeSyncTests: PersistenceTestCase {
    override func setUp() {
        super.setUp()
        Persistence.didOnboard = false
    }

    override func tearDown() {
        Persistence.didOnboard = false
        super.tearDown()
    }

    // MARK: startLaunchSyncIfOnboarded gating

    func testLaunchSyncRunsWhenOnboardedWithPlaylists() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = true
        let spotify = SpotifyFake()
        let state = makeState(messages: MessagesFake(uris: [uri(0), uri(1)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await waitUntil { state.syncStatus.lastSyncDate != nil }

        let appended = spotify.appended
        XCTAssertEqual(appended.flatMap { $0 }, [uri(0), uri(1)])
        XCTAssertEqual(Persistence.seen(forSpotifyID: "P").count, 2)
        // Home counts refreshed in place from the store.
        XCTAssertEqual(state.lists.first?.songCount, 2)
    }

    func testLaunchSyncNoOpWhenNotOnboarded() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = false
        let spotify = SpotifyFake()
        let state = makeState(messages: MessagesFake(uris: [uri(0)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await settle()

        let appended = spotify.appended
        XCTAssertNil(state.syncStatus.lastSyncDate)
        XCTAssertTrue(appended.isEmpty)
    }

    func testLaunchSyncNoOpWhenNoPlaylists() async {
        Persistence.didOnboard = true
        let spotify = SpotifyFake()
        let state = makeState(messages: MessagesFake(uris: [uri(0)]), spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await settle()

        let appended = spotify.appended
        XCTAssertTrue(state.lists.isEmpty)
        XCTAssertNil(state.syncStatus.lastSyncDate)
        XCTAssertTrue(appended.isEmpty)
    }

    func testLaunchSyncRunsOnlyOncePerLaunch() async {
        seedPlaylist(spotifyID: "P", chatGUID: "G")
        Persistence.didOnboard = true
        let spotify = SpotifyFake()
        // Fresh unseen URI: a second run, if the gate let it fire, would scan + append it.
        let messages = MessagesFake(uris: [uri(0), uri(1)])
        let state = makeState(messages: messages, spotify: spotify)
        state.reloadLists()

        state.startLaunchSyncIfOnboarded()
        await waitUntil { state.syncStatus.lastSyncDate != nil }
        // Pretend both URIs already synced so append-dedup alone can't mask a second run.
        Persistence.recordSeen(spotifyID: "P", uris: [uri(0), uri(1)])
        state.startLaunchSyncIfOnboarded()  // guarded: must not fire a second run
        await settle()

        // The once-per-launch flag — not seen-dedup — must be what blocks the second run.
        XCTAssertEqual(messages.scanCount, 1, "second launch call must not scan again")
        XCTAssertEqual(spotify.appended.count, 1)
    }

    // MARK: pre-expiry reconnect nudge threshold

    func testReconnectNudgeFiresInsideTwoWeekWindowOnly() {
        let state = makeState(messages: MessagesFake(uris: []), spotify: SpotifyFake())
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
        let state = makeState(messages: MessagesFake(uris: []), spotify: SpotifyFake())
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
// MessagesFake / SpotifyFake are shared — see TestSupport.swift.
