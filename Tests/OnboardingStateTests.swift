import XCTest
@testable import FriendList

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testFirstRunRoutesThroughSpotifySetup() async {
        let spotify = SpotifyFake()
        let state = makeState(spotify: spotify)
        state.step = 4

        await state.continueAfterScan()

        XCTAssertEqual(state.step, 5)
    }

    func testSameSessionRoutesDirectlyToCustomizeAndBackToScan() async {
        let state = makeState(spotify: SpotifyFake())
        state.connected = true
        state.step = 4

        await state.continueAfterScan()
        XCTAssertEqual(state.step, 7)

        state.back()
        XCTAssertEqual(state.step, 4)
    }

    func testRestoredSessionRoutesDirectlyToCustomize() async {
        let spotify = SpotifyFake(
            savedID: "saved-client",
            restored: SpotifySession(clientID: "saved-client", displayName: "Taylor")
        )
        let state = makeState(spotify: spotify)

        await state.restoreSpotifySession()
        state.step = 4
        await state.continueAfterScan()

        XCTAssertTrue(state.connected)
        XCTAssertEqual(state.clientId, "saved-client")
        XCTAssertEqual(state.spotifyDisplayName, "Taylor")
        XCTAssertEqual(state.step, 7)
    }

    func testMissingOrRevokedSessionFallsBackToSetup() async {
        for spotify in [
            SpotifyFake(),
            SpotifyFake(savedID: "saved-client", restoreError: SpotifyError.sessionExpired),
        ] {
            let state = makeState(spotify: spotify)
            await state.restoreSpotifySession()
            state.step = 4
            await state.continueAfterScan()

            XCTAssertFalse(state.connected)
            XCTAssertEqual(state.step, 5)
        }
    }

    func testAuthFailureDuringCreationReturnsToReconnectWithoutPersisting() async {
        let spotify = SpotifyFake(createError: SpotifyError.http(401, "expired"))
        let state = makeState(spotify: spotify)
        state.connected = true
        state.step = 8
        state.scannedTrackURIs = ["spotify:track:one"]

        await state.createPlaylist()

        XCTAssertFalse(state.connected)
        XCTAssertEqual(state.step, 5)
        XCTAssertTrue(state.lists.isEmpty)
        XCTAssertEqual(state.connectError, "Your Spotify session expired. Please reconnect.")
    }

    func testCreationReceivesScannedURIsAndPersistsPlaylist() async {
        let spotify = SpotifyFake()
        let persistence = PersistenceFake()
        let state = makeState(spotify: spotify, persistence: persistence)
        state.chats = [ChatSample(name: "Friends", links: 2, guid: "chat-guid")]
        state.pickedID = state.chats[0].id
        state.name = "Road trip"
        state.found = 2
        state.scannedTrackURIs = ["spotify:track:one", "spotify:track:two"]

        await state.createPlaylist()

        let request = spotify.lastCreateRequest
        XCTAssertEqual(request?.uris, state.scannedTrackURIs)
        XCTAssertEqual(state.lists.last?.name, "Road trip")
        XCTAssertEqual(state.lists.last?.spotifyID, "playlist-id")
        XCTAssertEqual(state.step, 9)
        XCTAssertEqual(persistence.savedPlaylists.last?.spotifyID, "playlist-id")
        XCTAssertEqual(persistence.seenURIs["playlist-id"], Set(state.scannedTrackURIs))
    }

    func testCancelConnectClearsConnectingWithoutError() async throws {
        let spotify = SpotifyFake()
        spotify.connectDelay = 60_000_000_000
        let state = makeState(spotify: spotify)
        state.step = 5
        state.clientId = "cid"

        let run = Task { await state.connectSpotify() }
        try await poll(until: state.connecting)
        XCTAssertTrue(state.connecting)

        state.cancelConnect()
        await run.value

        XCTAssertFalse(state.connecting)
        XCTAssertNil(state.connectError)
        XCTAssertFalse(state.connected)
        XCTAssertEqual(state.step, 5)
    }

    func testStaleScanResultIsDiscarded() async throws {
        let gate = DispatchSemaphore(value: 0)
        var messages = MessagesFake(uris: ["spotify:track:stale"])
        messages.scanGate = gate
        let state = makeState(spotify: SpotifyFake(), messages: messages)
        state.chats = [
            ChatSample(name: "A", links: 1, guid: "chat-a"),
            ChatSample(name: "B", links: 1, guid: "chat-b"),
        ]
        state.pickedID = "chat-a"
        state.step = 4

        let run = Task { await state.performScan() }
        try await poll(until: messages.scanCount > 0)
        XCTAssertEqual(messages.scanCount, 1)

        state.pickedID = "chat-b"
        gate.signal()
        await run.value

        XCTAssertTrue(state.scannedTrackURIs.isEmpty)
        XCTAssertEqual(state.found, 0)
        XCTAssertNil(state.scanError)
    }

    func testScanFailureSurfacesAnErrorInsteadOfEmptyResults() async {
        var messages = MessagesFake()
        messages.scanError = NSError(domain: "test", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: "database unreadable"])
        let state = makeState(spotify: SpotifyFake(), messages: messages)
        state.chats = [ChatSample(name: "Friends", links: 2, guid: "chat-guid")]
        state.pickedID = "chat-guid"

        await state.performScan()

        XCTAssertEqual(state.scanError, "database unreadable")
        XCTAssertTrue(state.scannedTrackURIs.isEmpty)
        XCTAssertEqual(state.scanPct, 1)
    }

    func testRetryAfterPartialCreateAppendsInsteadOfDuplicating() async {
        let spotify = SpotifyFake()
        spotify.partialCreation = (id: "playlist-id", url: "https://open.spotify.com/playlist/id", added: 1)
        let persistence = PersistenceFake()
        let state = makeState(spotify: spotify, persistence: persistence)
        state.connected = true
        state.step = 8
        state.chats = [ChatSample(name: "Friends", links: 3, guid: "chat-guid")]
        state.pickedID = "chat-guid"
        state.name = "Road trip"
        state.found = 3
        state.scannedTrackURIs = ["spotify:track:one", "spotify:track:two", "spotify:track:three"]

        await state.createPlaylist()

        XCTAssertNotNil(state.createError)
        XCTAssertEqual(state.step, 8)
        XCTAssertTrue(state.lists.isEmpty)

        spotify.partialCreation = nil
        await state.createPlaylist()

        XCTAssertEqual(spotify.createCallCount, 1)
        XCTAssertEqual(spotify.appended, [["spotify:track:two", "spotify:track:three"]])
        XCTAssertEqual(state.step, 9)
        XCTAssertNil(state.createError)
        XCTAssertEqual(state.lists.last?.spotifyID, "playlist-id")
        XCTAssertEqual(persistence.seenURIs["playlist-id"], Set(state.scannedTrackURIs))
    }

    func testPendingCreationDoesNotLeakAcrossChats() async {
        let spotify = SpotifyFake()
        spotify.partialCreation = (id: "playlist-a", url: "https://open.spotify.com/playlist/a", added: 1)
        let persistence = PersistenceFake()
        let state = makeState(spotify: spotify, persistence: persistence)
        state.connected = true
        state.step = 8
        state.chats = [ChatSample(name: "A", links: 2, guid: "chat-a"),
                       ChatSample(name: "B", links: 2, guid: "chat-b")]
        state.pickedID = "chat-a"
        state.scannedTrackURIs = ["spotify:track:a1", "spotify:track:a2"]
        await state.createPlaylist()

        state.go(to: 7); state.go(to: 4); state.go(to: 3)
        state.pickedID = "chat-b"
        state.scannedTrackURIs = ["spotify:track:b1", "spotify:track:b2", "spotify:track:b3"]
        state.go(to: 8)
        spotify.partialCreation = nil
        await state.createPlaylist()

        XCTAssertEqual(spotify.createCallCount, 2)
        XCTAssertEqual(spotify.appended, [])
        XCTAssertNotEqual(state.lists.last?.spotifyID, "playlist-a")
        XCTAssertNil(persistence.seenURIs["playlist-a"])
        XCTAssertEqual(state.lists.last?.chatGUID, "chat-b")
        XCTAssertEqual(persistence.seenURIs["playlist-id"], Set(state.scannedTrackURIs))
    }

    func testPendingCreationDroppedWhenRenamed() async {
        let spotify = SpotifyFake()
        spotify.partialCreation = (id: "playlist-a", url: "https://open.spotify.com/playlist/a", added: 1)
        let state = makeState(spotify: spotify)
        state.connected = true
        state.step = 8
        state.chats = [ChatSample(name: "Friends", links: 2, guid: "chat-guid")]
        state.pickedID = "chat-guid"
        state.name = "Original"
        state.scannedTrackURIs = ["spotify:track:one", "spotify:track:two"]
        await state.createPlaylist()

        state.go(to: 7)
        state.name = "Changed"
        state.go(to: 8)
        spotify.partialCreation = nil
        await state.createPlaylist()

        XCTAssertEqual(spotify.createCallCount, 2)
        XCTAssertEqual(spotify.appended, [])
        XCTAssertEqual(spotify.lastCreateRequest?.name, "Changed")
        XCTAssertEqual(state.lists.last?.name, "Changed")
    }

    func testRestoreRetriesAfterTransientFailure() async {
        let spotify = SpotifyFake(savedID: "cid", restoreError: SpotifyError.http(500, "server error"))
        let state = makeState(spotify: spotify)

        await state.restoreSpotifySession()
        XCTAssertFalse(state.connected)

        spotify.restoreError = nil
        spotify.restored = SpotifySession(clientID: "cid", displayName: "Taylor")
        await state.restoreSpotifySession()

        XCTAssertTrue(state.connected)
        XCTAssertEqual(state.spotifyDisplayName, "Taylor")
    }

    func testLateCreateCompletionKeepsCapturedNameAndStep() async throws {
        let spotify = SpotifyFake()
        spotify.createDelay = 300_000_000
        let state = makeState(spotify: spotify)
        state.connected = true
        state.step = 8
        state.chats = [ChatSample(name: "Friends", links: 1, guid: "chat-guid")]
        state.pickedID = "chat-guid"
        state.name = "Original"
        state.scannedTrackURIs = ["spotify:track:one"]

        let run = Task { await state.createPlaylist() }
        try await poll(until: spotify.lastCreateRequest != nil)
        state.go(to: 7)
        state.name = "Changed"
        await run.value

        XCTAssertEqual(state.step, 7)
        XCTAssertEqual(spotify.lastCreateRequest?.name, "Original")
        XCTAssertEqual(state.lists.last?.name, "Original")
    }

    func testReloadChatsSkipsWhenAlreadyLoadedAndKeepsSelection() async throws {
        var messages = MessagesFake()
        messages.chats = [GroupChat(guid: "chat-guid", name: "Friends", messageCount: 10, lastDate: 0, linkCount: 2)]
        let state = makeState(spotify: SpotifyFake(), messages: messages)

        state.reloadChats()
        try await poll(until: !state.chats.isEmpty)
        XCTAssertEqual(state.chats.first?.id, "chat-guid")

        state.pickedID = "chat-guid"
        state.reloadChats()

        XCTAssertEqual(messages.groupChatsCount, 1)
        XCTAssertEqual(state.pickedChat?.guid, "chat-guid")
    }

    /// Polls until `condition` holds (up to ~3s); the caller asserts the awaited outcome after.
    private func poll(until condition: @autoclosure () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeState(spotify: SpotifyFake,
                           persistence: PersistenceProviding = PersistenceFake(),
                           messages: MessagesFake = MessagesFake()) -> OnboardingState {
        let state = OnboardingState(messages: messages, spotify: spotify, persistence: persistence)
        state.lists = []
        return state
    }
}

private final class PersistenceFake: PersistenceProviding {
    var didOnboard = false
    var authorizationDate: Date?
    var savedPlaylists: [SavedPlaylist] = []
    var seenURIs: [String: Set<String>] = [:]

    func loadPlaylists() -> [SavedPlaylist]? { savedPlaylists }
    // Delegates to the real matching/upsert core so the fake cannot drift from production behavior.
    func upsertPlaylists(_ updates: [SavedPlaylist]) { Persistence.upsert(updates, into: &savedPlaylists) }
    func recordSeen(spotifyID: String, uris: [String]) { seenURIs[spotifyID, default: []].formUnion(uris) }
    func seen(forSpotifyID id: String) -> Set<String> { seenURIs[id] ?? [] }
}
// MessagesFake / SpotifyFake are shared — see TestSupport.swift.
