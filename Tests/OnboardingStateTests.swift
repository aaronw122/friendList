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

        let request = await spotify.lastCreateRequest
        XCTAssertEqual(request?.uris, state.scannedTrackURIs)
        XCTAssertEqual(state.lists.last?.name, "Road trip")
        XCTAssertEqual(state.lists.last?.spotifyID, "playlist-id")
        XCTAssertEqual(state.step, 9)
        XCTAssertEqual(persistence.savedPlaylists.last?.spotifyID, "playlist-id")
        XCTAssertEqual(persistence.seenURIs["playlist-id"], Set(state.scannedTrackURIs))
    }

    private func makeState(spotify: SpotifyFake,
                           persistence: PersistenceProviding = PersistenceFake()) -> OnboardingState {
        let state = OnboardingState(messages: MessagesFake(), spotify: spotify, persistence: persistence)
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
    func upsertPlaylists(_ updates: [SavedPlaylist]) {
        for update in updates {
            if let i = savedPlaylists.firstIndex(where: {
                update.spotifyID.isEmpty ? ($0.name == update.name && $0.chatGUID == update.chatGUID)
                                         : $0.spotifyID == update.spotifyID
            }) {
                savedPlaylists[i] = update
            } else {
                savedPlaylists.append(update)
            }
        }
    }
    func recordSeen(spotifyID: String, uris: [String]) { seenURIs[spotifyID, default: []].formUnion(uris) }
    func seen(forSpotifyID id: String) -> Set<String> { seenURIs[id] ?? [] }
}

private struct MessagesFake: MessagesReading {
    func canRead() -> Bool { true }
    func groupChats() throws -> [GroupChat] { [] }
    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        ChatScan(trackURIs: [], youtubeCount: 0, messagesScanned: 0)
    }
}

private actor SpotifyFake: SpotifyProviding {
    struct CreateRequest: Equatable {
        let name: String
        let description: String
        let uris: [String]
    }

    let savedID: String?
    let restored: SpotifySession?
    let restoreError: Error?
    let createError: Error?
    private(set) var lastCreateRequest: CreateRequest?

    init(savedID: String? = nil,
         restored: SpotifySession? = nil,
         restoreError: Error? = nil,
         createError: Error? = nil) {
        self.savedID = savedID
        self.restored = restored
        self.restoreError = restoreError
        self.createError = createError
    }

    func savedClientID() -> String? { savedID }

    func restoreSession() throws -> SpotifySession? {
        if let restoreError { throw restoreError }
        return restored
    }

    func connect(clientID: String) async throws -> String { "Connected User" }

    func createPlaylist(name: String,
                        description: String,
                        trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        lastCreateRequest = CreateRequest(name: name, description: description, uris: trackURIs)
        if let createError { throw createError }
        progress(1, "Done")
        return SpotifyPlaylistResult(id: "playlist-id", url: "https://open.spotify.com/playlist/id", added: trackURIs.count)
    }
}
