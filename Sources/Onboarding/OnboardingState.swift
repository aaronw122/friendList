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
    @ObservationIgnored private var accessPollTask: Task<Void, Never>?
    @ObservationIgnored private var createInFlight = false
    @ObservationIgnored private var chatsLoading = false

    init(messages: MessagesReading? = nil, spotify: SpotifyProviding? = nil) {
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
        self.lists = Persistence.loadPlaylists().map {
            Playlist(name: $0.name, songCount: $0.songCount, chatName: $0.chatName,
                     externalURL: $0.externalURL, spotifyID: $0.spotifyID, chatGUID: $0.chatGUID)
        }
        if !isPreview && Persistence.didOnboard && !lists.isEmpty {
            step = 0
            sheetIn = false
            probeAccessOnAppear()   // warm the chat list so "Create a new one" is instant
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

    // Enumerating group chats scans a large recent-message window, so run it off
    // the main thread — otherwise it blocks the click and transition into the picker.
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
            createLabel = "Couldn't finish: \(error.localizedDescription)"
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
        persistAllPlaylists()
        if let guid = pickedChat?.guid {
            Persistence.recordSeen(chatGUID: guid, uris: scannedTrackURIs)
        }
        Persistence.didOnboard = true
        go(to: 9)
    }

    /// Persist each playlist with its own Spotify ID and chat GUID to prevent cross-row association.
    private func persistAllPlaylists() {
        Persistence.savePlaylists(lists.map {
            SavedPlaylist(spotifyID: $0.spotifyID, name: $0.name, songCount: $0.songCount,
                          chatName: $0.chatName, chatGUID: $0.chatGUID, externalURL: $0.externalURL)
        })
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
