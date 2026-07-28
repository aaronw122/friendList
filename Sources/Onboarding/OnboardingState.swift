import SwiftUI
import Observation

// MARK: - Models

struct ChatSample: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let links: Int
    var pinned: Bool = false
    var guid: String? = nil
}

struct Playlist: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var songCount: Int
    var chatName: String
    var externalURL: String = ""
    var spotifyID: String = ""
    var chatGUID: String = ""
}

// MARK: - Onboarding state machine

@Observable
final class OnboardingState {
    var step: Int = 1
    var sheetIn: Bool = false
    var goingBack: Bool = false

    var access: Bool = false
    var pickedID: UUID? = nil
    var chatSearch: String = ""
    var loadError: String? = nil

    var clientId: String = ""
    var connected: Bool = false
    var connecting: Bool = false
    var connectError: String? = nil
    var spotifyDisplayName: String = ""
    var copied: Bool = false

    var name: String = ""
    var desc: String = "made by friendList :)"

    var scanPct: Double = 0
    var scanLabel: String = ""
    var found: Int = 0
    var createPct: Double = 0
    var createLabel: String = ""

    var scannedTrackURIs: [String] = []
    var youtubeCount: Int = 0

    var lists: [Playlist] = []
    var lastCreatedURL: String = ""

    var chats: [ChatSample] = []

    // MARK: Services (injected; real by default, sample under previews)

    @ObservationIgnored let messages: MessagesReading
    @ObservationIgnored let spotify: SpotifyProviding
    @ObservationIgnored var persistence: PersistenceProviding
    @ObservationIgnored private var accessPollTask: Task<Void, Never>?
    @ObservationIgnored private var createInFlight = false
    @ObservationIgnored private var chatsLoading = false
    @ObservationIgnored private var restoreTask: Task<SpotifyRestoreResult, Never>?

    private struct SpotifyRestoreResult: Sendable {
        let clientID: String?
        let result: Result<SpotifySession?, Error>
    }

    init(messages: MessagesReading? = nil,
         spotify: SpotifyProviding? = nil,
         persistence: PersistenceProviding = AppPersistence()) {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if let messages {
            self.messages = messages
        } else {
            self.messages = isPreview ? SampleMessagesReader() : MessagesReader()
        }
        if let spotify {
            self.spotify = spotify
        } else {
            self.spotify = isPreview ? FakeSpotify() : SpotifyService()
        }
        self.persistence = persistence
        self.lists = (persistence.loadPlaylists() ?? []).map {
            Playlist(name: $0.name, songCount: $0.songCount, chatName: $0.chatName,
                     externalURL: $0.externalURL, spotifyID: $0.spotifyID, chatGUID: $0.chatGUID)
        }
        if !isPreview && persistence.didOnboard && !lists.isEmpty {
            step = 0
            sheetIn = false
            probeAccessOnAppear()
        }
        if isPreview {
            access = true
            reloadChats()
        }
    }

    var visibleChats: [ChatSample] {
        let q = chatSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? chats : chats.filter { $0.name.lowercased().contains(q) }
        // Rank by song count, preserve source recency for ties, and keep pinned chats first.
        let ranked = base.enumerated().sorted { a, b in
            a.element.links != b.element.links
                ? a.element.links > b.element.links
                : a.offset < b.offset
        }.map(\.element)
        return ranked.filter(\.pinned) + ranked.filter { !$0.pinned }
    }

    var pickedChat: ChatSample? { chats.first { $0.id == pickedID } }
    var selectedChatName: String { pickedChat?.name ?? "" }
    var selectedChatLinks: Int { pickedChat?.links ?? 0 }

    var canAdvance: Bool {
        switch step {
        case 2: return access
        case 3: return pickedID != nil
        default: return true
        }
    }

    var progressFraction: Double {
        let table: [Double] = [0, 0, 0.12, 0.24, 0.40, 0.55, 0.68, 0.82, 0.93, 1.0]
        return table[min(max(step, 0), 9)]
    }

    // MARK: - Full Disk Access

    func probeAccessOnAppear() {
        let reader = messages
        Task { @MainActor in
            let ok = await Task.detached(priority: .userInitiated) { reader.canRead() }.value
            if ok {
                access = true
                reloadChats()
            }
        }
    }

    /// Poll after opening Settings because FDA may apply live or require relaunch via the resume marker.
    func requestAccess() {
        Persistence.resumeAtPicker = true
        FullDiskAccess.openSettings()
        startAccessPolling()
    }

    func cancelAccessPolling() {
        accessPollTask?.cancel()
        accessPollTask = nil
    }

    private func startAccessPolling() {
        accessPollTask?.cancel()
        accessPollTask = Task { @MainActor [weak self] in
            for _ in 0..<160 {
                if Task.isCancelled { return }
                if self?.messages.canRead() == true {
                    self?.access = true
                    self?.reloadChats()
                    Persistence.resumeAtPicker = false
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // Runs off the main thread; the chat scan is heavy enough to stall the picker transition.
    func reloadChats() {
        guard !chatsLoading else { return }
        chatsLoading = true
        let reader = messages
        Task { @MainActor in
            defer { chatsLoading = false }
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try reader.groupChats().map {
                        ChatSample(name: $0.name, links: $0.linkCount, pinned: false, guid: $0.guid)
                    }
                }.value
                chats = loaded
                loadError = nil
            } catch {
                chats = []
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Scan (M1)

    @MainActor
    func performScan() async {
        guard let guid = pickedChat?.guid else {
            scanPct = 1; scanLabel = "No chat selected"; return
        }
        scanLabel = "Opening the local Messages database…"
        scanPct = 0
        found = 0

        let reader = messages
        let result: ChatScan = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let scan = try reader.scan(chatGUID: guid) { p in
                        DispatchQueue.main.async { [weak self] in
                            self?.scanPct = p.fraction
                            self?.found = p.found
                            self?.scanLabel = p.label
                        }
                    }
                    cont.resume(returning: scan)
                } catch {
                    DispatchQueue.main.async { [weak self] in self?.loadError = error.localizedDescription }
                    cont.resume(returning: ChatScan(trackURIs: [], youtubeCount: 0, messagesScanned: 0))
                }
            }
        }

        scannedTrackURIs = result.trackURIs
        youtubeCount = result.youtubeCount
        found = result.trackURIs.count
        scanPct = 1
        scanLabel = result.trackURIs.isEmpty
            ? "No Spotify links found in this chat"
            : "Found \(result.trackURIs.count) songs"
    }

    // MARK: - Spotify connect (M2)

    @MainActor
    func restoreSpotifySession() async {
        guard !connected else { return }

        let restoration = await spotifyRestorationResult()
        applySpotifyRestoration(restoration)
    }

    @MainActor
    private func spotifyRestorationResult() async -> SpotifyRestoreResult {
        let task: Task<SpotifyRestoreResult, Never>
        if let restoreTask {
            task = restoreTask
        } else {
            let provider = spotify
            task = Task {
                let clientID = await provider.savedClientID()
                do {
                    return SpotifyRestoreResult(clientID: clientID, result: .success(try await provider.restoreSession()))
                } catch {
                    return SpotifyRestoreResult(clientID: clientID, result: .failure(error))
                }
            }
            restoreTask = task
        }

        return await task.value
    }

    @MainActor
    private func applySpotifyRestoration(_ restoration: SpotifyRestoreResult) {
        clientId = restoration.clientID ?? ""
        guard !clientId.isEmpty else { return }

        switch restoration.result {
        case .success(let restoredSession):
            guard let session = restoredSession else { return }
            clientId = session.clientID
            spotifyDisplayName = session.displayName
            connected = true
            connectError = nil
        case .failure(let error):
            if error.isSpotifyAuthenticationFailure {
                connected = false
                connectError = "Your Spotify session expired. Please reconnect."
            } else {
                // A temporary network or API failure must not discard an otherwise reusable session.
                connectError = "Couldn't check Spotify right now: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    func continueAfterScan() async {
        await restoreSpotifySession()
        go(to: connected ? 7 : 5)
    }

    @MainActor
    func connectSpotify() async {
        let fromStep = step
        if connected {
            if step == fromStep { advance() }
            return
        }
        let id = clientId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !connecting else { return }
        connecting = true
        connectError = nil
        do {
            let name = try await spotify.connect(clientID: id)
            spotifyDisplayName = name
            connected = true
            connecting = false
            // Browser auth may finish after navigation; advance only if the consent screen is still active.
            if step == fromStep { advance() }
        } catch {
            connecting = false
            connectError = error.localizedDescription
        }
    }

    @MainActor
    func createPlaylist() async {
        guard !createInFlight else { return }
        createInFlight = true
        defer { createInFlight = false }

        createPct = 0
        createLabel = "Creating the playlist on Spotify…"
        let playlistName = name.isEmpty ? selectedChatName : name
        let description = desc
        let uris = scannedTrackURIs
        do {
            let result = try await spotify.createPlaylist(
                name: playlistName, description: description, trackURIs: uris
            ) { frac, label in
                Task { @MainActor in
                    // Progress callbacks can arrive out of order, so the displayed value must not regress.
                    self.createPct = max(self.createPct, frac)
                    self.createLabel = label
                }
            }
            createPct = 1
            completeCreation(externalURL: result.url, spotifyID: result.id)
        } catch {
            if error.isSpotifyAuthenticationFailure {
                connected = false
                connectError = "Your Spotify session expired. Please reconnect."
                go(to: 5)
            } else {
                createLabel = "Couldn't finish: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Navigation

    func go(to newStep: Int) {
        goingBack = newStep < step
        step = newStep
        sheetIn = newStep > 1
    }

    func advance() {
        guard canAdvance else { return }
        go(to: min(step + 1, 9))
    }

    var canGoBack: Bool { (2...8).contains(step) }

    func back() {
        switch step {
        case 5: go(to: 3)
        case 7 where connected: go(to: 4)
        case 3: go(to: lists.isEmpty ? 2 : 0)
        case 0, 1: break
        default: go(to: max(step - 1, 1))
        }
    }

    func completeCreation(externalURL: String = "", spotifyID: String = "") {
        let pl = Playlist(
            name: name.isEmpty ? selectedChatName : name,
            songCount: found,
            chatName: selectedChatName,
            externalURL: externalURL,
            spotifyID: spotifyID,
            chatGUID: pickedChat?.guid ?? ""
        )
        // Prefer Spotify ID identity; name and chat are only a fallback when no ID exists.
        let matchIdx = lists.firstIndex(where: {
            if !spotifyID.isEmpty { return $0.spotifyID == spotifyID }
            return $0.name == pl.name && $0.chatGUID == pl.chatGUID
        })
        if let idx = matchIdx {
            lists[idx] = pl
        } else {
            lists.append(pl)
        }
        lastCreatedURL = externalURL
        persistPlaylist(pl)
        if !spotifyID.isEmpty {
            persistence.recordSeen(spotifyID: spotifyID, uris: scannedTrackURIs)
        }
        persistence.didOnboard = true
        go(to: 9)
    }

    private func persistPlaylist(_ playlist: Playlist) {
        persistence.upsertPlaylists([
            SavedPlaylist(spotifyID: playlist.spotifyID, name: playlist.name,
                          songCount: playlist.songCount, chatName: playlist.chatName,
                          chatGUID: playlist.chatGUID, externalURL: playlist.externalURL)
        ])
    }

    func goHome() { go(to: 0) }

    func createAnother() {
        pickedID = nil
        chatSearch = ""
        scannedTrackURIs = []
        youtubeCount = 0
        found = 0
        name = ""
        scanPct = 0
        createPct = 0
        go(to: 3)
    }

    func seedNameIfNeeded() {
        if name.isEmpty { name = selectedChatName }
    }
}
