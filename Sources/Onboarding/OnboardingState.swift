import SwiftUI
import Observation

// MARK: - Models

struct ChatSample: Identifiable, Hashable {
    // Identity is the stable chat GUID so reloads never invalidate a selection.
    var id: String { guid }
    let name: String
    let links: Int
    var pinned: Bool = false
    let guid: String
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

@MainActor
@Observable
final class OnboardingState {
    var step: Int = 1
    var sheetIn: Bool = false
    var goingBack: Bool = false

    var access: Bool = false
    var pickedID: String? = nil
    var chatSearch: String = ""
    var scanError: String? = nil
    var createError: String? = nil

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
    var shortLinkCount: Int = 0

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
    @ObservationIgnored private var connectTask: Task<String, Error>?
    @ObservationIgnored private var pendingCreation: PendingCreation?

    // A playlist that was created but only partially filled; retry appends instead of re-creating.
    private struct PendingCreation {
        let id: String
        let url: String
        let chatGUID: String
        let name: String
        var added: Int
    }

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
        self.lists = Self.mapped(persistence.loadPlaylists() ?? [])
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

    /// FDA can apply live; polling notices the grant without a relaunch.
    func requestAccess() {
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
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // Run the chat scan off-main to avoid stalling the picker transition.
    func reloadChats() {
        // Loaded data stays put; a re-appearing picker must not re-run the expensive link-count pass.
        guard chats.isEmpty, !chatsLoading else { return }
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
            } catch {
                chats = []
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
        scanError = nil

        let reader = messages
        let outcome: Result<ChatScan, Error> = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let scan = try reader.scan(chatGUID: guid) { p in
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.pickedChat?.guid == guid else { return }
                            self.scanPct = p.fraction
                            self.found = p.found
                            self.scanLabel = p.label
                        }
                    }
                    cont.resume(returning: .success(scan))
                } catch {
                    cont.resume(returning: .failure(error))
                }
            }
        }

        // A stale scan of an abandoned chat must never overwrite the current selection's results.
        guard pickedChat?.guid == guid else { return }

        switch outcome {
        case .success(let result):
            scannedTrackURIs = result.trackURIs
            youtubeCount = result.youtubeCount
            shortLinkCount = result.spotifyShortLinkCount
            found = result.trackURIs.count
            scanPct = 1
            scanLabel = result.trackURIs.isEmpty
                ? "No Spotify links found in this chat"
                : "Found \(result.trackURIs.count) songs"
        case .failure(let error):
            scanPct = 1
            scanError = error.localizedDescription
            scanLabel = "Couldn't read this chat"
        }
    }

    // MARK: - Spotify connect (M2)

    @MainActor
    func restoreSpotifySession() async {
        guard !connected else { return }

        let restoration = await spotifyRestorationResult()
        // A failed probe must not stay memoized; the next attempt retries the restore.
        if case .failure = restoration.result { restoreTask = nil }
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
                // Preserve a reusable session across transient network and API failures.
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
        if connected {
            advance()
            return
        }
        let id = clientId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !connecting else { return }
        let entryStep = step
        connecting = true
        connectError = nil
        // Held as a task so cancelConnect() can tear down the browser wait.
        let spotify = self.spotify
        let task = Task { try await spotify.connect(clientID: id) }
        connectTask = task
        defer { connectTask = nil }
        do {
            let name = try await task.value
            // Consent and reconnect reset the six-month refresh-token nudge clock.
            persistence.authorizationDate = Date()
            spotifyDisplayName = name
            connected = true
            connecting = false
            // Browser auth may finish after navigation, so advance only from the consent screen.
            if step == entryStep { advance() }
        } catch is CancellationError {
            connecting = false
        } catch {
            connecting = false
            connectError = error.localizedDescription
        }
    }

    @MainActor
    func cancelConnect() {
        connectTask?.cancel()
    }

    @MainActor
    func createPlaylist() async {
        guard !createInFlight else { return }
        createInFlight = true
        defer { createInFlight = false }

        // Capture everything at entry so a completion after navigation can't read drifted state.
        let entryStep = step
        let playlistName = name.isEmpty ? selectedChatName : name
        let chatName = selectedChatName
        let chatGUID = pickedChat?.guid ?? ""
        let uris = scannedTrackURIs

        createError = nil
        createPct = 0
        createLabel = "Creating the playlist on Spotify…"
        do {
            let result = try await createOrResume(name: playlistName, description: desc,
                                                  chatGUID: chatGUID, uris: uris)
            pendingCreation = nil
            createPct = 1
            finishCreation(named: playlistName, chatName: chatName, chatGUID: chatGUID,
                           uris: uris, externalURL: result.url, spotifyID: result.id,
                           navigate: step == entryStep)
        } catch {
            let underlying = (error as? SpotifyPartialCreationFailure)?.underlying ?? error
            if underlying.isSpotifyAuthenticationFailure {
                connected = false
                connectError = "Your Spotify session expired. Please reconnect."
                if step == entryStep { go(to: 5) }
            } else if step == entryStep {
                createError = underlying.localizedDescription
                createLabel = "Couldn't finish"
            }
        }
    }

    // Resumes a partially filled playlist when one exists; otherwise creates from scratch.
    @MainActor
    private func createOrResume(name: String, description: String, chatGUID: String, uris: [String]) async throws -> SpotifyPlaylistResult {
        // A pending playlist resumes only for the same chat and name; any other context abandons it.
        if let pending = pendingCreation, pending.chatGUID != chatGUID || pending.name != name {
            pendingCreation = nil
        }
        if let pending = pendingCreation {
            return try await resumePendingCreation(pending, name: name, chatGUID: chatGUID, uris: uris)
        }
        return try await createNewPlaylist(name: name, description: description, chatGUID: chatGUID, uris: uris)
    }

    // Appends only the tracks that haven't landed yet, so retry never duplicates.
    @MainActor
    private func resumePendingCreation(_ pending: PendingCreation, name: String, chatGUID: String, uris: [String]) async throws -> SpotifyPlaylistResult {
        createLabel = "Adding the remaining tracks…"
        let remaining = Array(uris.dropFirst(pending.added))
        var addedTrackCount = pending.added
        do {
            _ = try await spotify.appendTracks(playlistID: pending.id, trackURIs: remaining) { batch in
                addedTrackCount += batch.count
            }
            return SpotifyPlaylistResult(id: pending.id, url: pending.url, added: uris.count)
        } catch {
            pendingCreation = PendingCreation(id: pending.id, url: pending.url,
                                              chatGUID: chatGUID, name: name, added: addedTrackCount)
            throw error
        }
    }

    @MainActor
    private func createNewPlaylist(name: String, description: String, chatGUID: String, uris: [String]) async throws -> SpotifyPlaylistResult {
        do {
            return try await spotify.createPlaylist(name: name, description: description, trackURIs: uris) { frac, label in
                Task { @MainActor in
                    // Out-of-order progress callbacks must not regress the displayed value.
                    self.createPct = max(self.createPct, frac)
                    self.createLabel = label
                }
            }
        } catch let partial as SpotifyPartialCreationFailure {
            // The playlist exists on Spotify; remember it so retry appends instead of duplicating.
            pendingCreation = PendingCreation(id: partial.id, url: partial.url,
                                              chatGUID: chatGUID, name: name, added: partial.added)
            throw partial
        }
    }

    @MainActor
    func reloadLists() {
        lists = Self.mapped(persistence.loadPlaylists() ?? [])
    }

    /// Nudge reconnection two weeks before six-month expiry while the token still works.
    func reconnectNudgeActive(now: Date = Date()) -> Bool {
        guard let authorized = persistence.authorizationDate else { return false }
        let cal = Calendar.current
        guard let anniversary = cal.date(byAdding: .month, value: 6, to: authorized),
              let windowStart = cal.date(byAdding: .day, value: -14, to: anniversary) else { return false }
        return now >= windowStart && now < anniversary
    }

    func beginReconnect() {
        connected = false
        go(to: 5)
    }

    private static func mapped(_ saved: [SavedPlaylist]) -> [Playlist] {
        saved.map {
            Playlist(name: $0.name, songCount: $0.songCount, chatName: $0.chatName,
                     externalURL: $0.externalURL, spotifyID: $0.spotifyID, chatGUID: $0.chatGUID)
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

    private func finishCreation(named playlistName: String, chatName: String, chatGUID: String,
                        uris: [String], externalURL: String, spotifyID: String,
                        navigate: Bool) {
        let pl = Playlist(
            name: playlistName,
            songCount: uris.count,
            chatName: chatName,
            externalURL: externalURL,
            spotifyID: spotifyID,
            chatGUID: chatGUID
        )
        // Spotify ID is canonical; use name and chat only when it is absent.
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
            persistence.recordSeen(spotifyID: spotifyID, uris: uris)
        }
        persistence.didOnboard = true
        // Record-keeping always happens; navigation only when the user is still on the creating step.
        if navigate { go(to: 9) }
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
        shortLinkCount = 0
        found = 0
        name = ""
        scanPct = 0
        createPct = 0
        scanError = nil
        createError = nil
        pendingCreation = nil
        go(to: 3)
    }

    func seedNameIfNeeded() {
        if name.isEmpty { name = selectedChatName }
    }
}
