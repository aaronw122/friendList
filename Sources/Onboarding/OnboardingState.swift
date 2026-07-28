import SwiftUI
import Observation

// MARK: - Models

struct ChatSample: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let links: Int
    var pinned: Bool = false
    var guid: String? = nil   // real chat.db guid; nil for pure samples
    // Recency is represented by position in the `chats` array (index 0 = most recent).
}

struct Playlist: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var songCount: Int
    var chatName: String
    var externalURL: String = ""   // Spotify web URL (populated in M2)
    var spotifyID: String = ""     // Spotify playlist id (populated in M2)
    var chatGUID: String = ""      // source chat (for future re-sync)
}

// MARK: - Onboarding state machine
//
// step: 0 = home, 1 = welcome, 2 = permissions, 3 = pick chat, 4 = scanning,
// 5 = Spotify keys, 6 = OAuth consent, 7 = customize, 8 = creating,
// 9 = all set. Navigation is linear 1→2→…→9→home(0); Home → 3.
// See handoff "Interactions & Behavior".

@Observable
final class OnboardingState {
    var step: Int = 1
    var sheetIn: Bool = false
    var goingBack: Bool = false

    // Chat selection
    var access: Bool = false          // Full Disk Access granted (real probe)
    var pickedID: UUID? = nil         // selected chat id
    var chatSearch: String = ""       // picker search query
    var loadError: String? = nil      // surfaced if chat enumeration fails

    // Spotify (PKCE — client id only, NO secret)
    var clientId: String = ""
    var connected: Bool = false       // becomes true after OAuth
    var connecting: Bool = false      // OAuth in flight (browser open)
    var connectError: String? = nil   // surfaced auth failure
    var spotifyDisplayName: String = ""
    var copied: Bool = false          // transient copy feedback (1400ms)

    // Customize
    var name: String = ""
    var desc: String = "made by friendList :)"

    // Loaders
    var scanPct: Double = 0
    var scanLabel: String = ""
    var found: Int = 0
    var createPct: Double = 0
    var createLabel: String = ""

    // Scan output (drives creation + counts)
    var scannedTrackURIs: [String] = []
    var youtubeCount: Int = 0

    // Home
    var lists: [Playlist] = []
    var lastCreatedURL: String = ""   // the playlist created in THIS run (for All-set)

    /// Group chats for the picker — populated from Messages at runtime (empty
    /// until Full Disk Access is granted and `loadChats()` runs).
    var chats: [ChatSample] = []

    // MARK: Services (injected; real by default, sample under previews)

    @ObservationIgnored let messages: MessagesReading
    @ObservationIgnored let spotify: SpotifyProviding
    @ObservationIgnored private var accessPollTask: Task<Void, Never>?
    @ObservationIgnored private var createInFlight = false

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
        // Restore any previously created playlists so Home survives quit.
        self.lists = Persistence.loadPlaylists().map {
            Playlist(name: $0.name, songCount: $0.songCount, chatName: $0.chatName,
                     externalURL: $0.externalURL, spotifyID: $0.spotifyID, chatGUID: $0.chatGUID)
        }
        // A returning user who already finished onboarding lands on Home (step 0),
        // where their persisted playlists live — not back on Welcome.
        if !isPreview && Persistence.didOnboard && !lists.isEmpty {
            step = 0
            sheetIn = false
        }
        // Previews want a populated picker without a real FDA grant.
        if isPreview {
            access = true
            reloadChats()
        }
    }

    /// Search-filtered, pinned-first, recency-ordered list for the picker.
    var visibleChats: [ChatSample] {
        let q = chatSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? chats : chats.filter { $0.name.lowercased().contains(q) }
        // Rank by song count (the whole point — surface the music chats first),
        // breaking ties by the original recency order (`chats` arrives last-date
        // DESC). enumerated() keeps that tiebreak stable across Swift's unstable
        // sort. Pinned chats still float to the top.
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

    /// Continue is gated on Permissions (needs access) and Pick chat (needs a pick).
    var canAdvance: Bool {
        switch step {
        case 2: return access
        case 3: return pickedID != nil
        default: return true
        }
    }

    /// Sheet-top progress width by step (2→12% … 9→100%).
    var progressFraction: Double {
        let table: [Double] = [0, 0, 0.12, 0.24, 0.40, 0.55, 0.68, 0.82, 0.93, 1.0]
        return table[min(max(step, 0), 9)]
    }

    // MARK: - Full Disk Access

    /// Probe on appearance; if already granted, load chats immediately.
    func probeAccessOnAppear() {
        if messages.canRead() {
            access = true
            reloadChats()
        }
    }

    /// User tapped "Grant access": open System Settings and poll until the read
    /// succeeds (macOS may or may not require a relaunch — the resume marker
    /// covers the relaunch case).
    func requestAccess() {
        Persistence.resumeAtPicker = true
        FullDiskAccess.openSettings()
        startAccessPolling()
    }

    /// Stop probing chat.db (called when the picker disappears).
    func cancelAccessPolling() {
        accessPollTask?.cancel()
        accessPollTask = nil
    }

    private func startAccessPolling() {
        accessPollTask?.cancel()
        accessPollTask = Task { @MainActor [weak self] in
            for _ in 0..<160 {   // ~4 min at 1.5s
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

    func reloadChats() {
        do {
            let gcs = try messages.groupChats()
            chats = gcs.map { ChatSample(name: $0.name, links: $0.linkCount, pinned: false, guid: $0.guid) }
            loadError = nil
        } catch {
            chats = []
            loadError = error.localizedDescription
        }
    }

    // MARK: - Scan (M1)

    /// Real scan of the selected chat's history. Runs off the main actor and
    /// streams progress back into `scanPct` / `found` / `scanLabel`.
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

    /// Run the real PKCE browser authorization. On success, advance to Scanning.
    /// Already connected (e.g. "create another") → reuse the session, no re-auth.
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
            // Don't yank the user forward if they navigated away during the browser auth.
            if step == fromStep { advance() }
        } catch {
            connecting = false
            connectError = error.localizedDescription
        }
    }

    /// Create the playlist on Spotify and populate it with the scanned tracks.
    /// Guarded against re-entry so a re-tap / view rebuild can't create duplicates.
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
                    // Progress callbacks can arrive out of order; never let the bar go backward.
                    self.createPct = max(self.createPct, frac)
                    self.createLabel = label
                }
            }
            createPct = 1
            completeCreation(externalURL: result.url, spotifyID: result.id)
        } catch {
            createLabel = "Couldn't finish: \(error.localizedDescription)"
            // Leave the user on the Creating screen with the error; Back still works.
        }
    }

    // MARK: - Navigation

    func go(to newStep: Int) {
        goingBack = newStep < step
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            step = newStep
            sheetIn = newStep > 1
        }
    }

    func advance() {
        guard canAdvance else { return }
        go(to: min(step + 1, 9))
    }

    /// Whether a back navigation is available from the current step.
    /// Steps 2–8 (the flow); All-set (9) has its own "Back to friendList".
    var canGoBack: Bool { (2...8).contains(step) }

    func back() {
        switch step {
        case 5: go(to: 3)                 // SpotifyKeys → Pick chat (skip the auto-
                                          // advancing Scanning step, which would
                                          // otherwise re-scan and bounce us forward)
        case 2: go(to: lists.isEmpty ? 1 : 0)  // Pick chat → Welcome on first run;
                                          // → Home when playlists already exist (the
                                          // user arrived here via "Create a new one").
        case 0, 1: break                  // no back from Home / Welcome
        default: go(to: max(step - 1, 1))
        }
    }

    /// Called when the Creating loader (step 7) completes: append the created
    /// playlist to Home, persist it, then advance to the All-set screen (step 8).
    func completeCreation(externalURL: String = "", spotifyID: String = "") {
        let pl = Playlist(
            name: name.isEmpty ? selectedChatName : name,
            songCount: found,
            chatName: selectedChatName,
            externalURL: externalURL,
            spotifyID: spotifyID,
            chatGUID: pickedChat?.guid ?? ""
        )
        // Identify an existing playlist by its Spotify id when we have one; only
        // fall back to (name, chat) when there's no id (so a genuinely new playlist
        // that happens to share a name can't overwrite an older row).
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
        // In-app dedup: remember what we added for this chat.
        if let guid = pickedChat?.guid {
            Persistence.recordSeen(chatGUID: guid, uris: scannedTrackURIs)
        }
        Persistence.didOnboard = true
        go(to: 9)
    }

    /// Persist every playlist 1:1 — each row keeps its OWN spotifyID/chatGUID
    /// (no cross-row smearing).
    private func persistAllPlaylists() {
        Persistence.savePlaylists(lists.map {
            SavedPlaylist(spotifyID: $0.spotifyID, name: $0.name, songCount: $0.songCount,
                          chatName: $0.chatName, chatGUID: $0.chatGUID, externalURL: $0.externalURL)
        })
    }

    /// From All-set (step 8) → Home. Playlist already appended at completeCreation().
    func goHome() { go(to: 0) }

    /// Home "Create a new one" → back to chat picker, preserving auth + keys.
    func createAnother() {
        pickedID = nil
        chatSearch = ""
        scannedTrackURIs = []
        youtubeCount = 0
        found = 0
        name = ""              // reseeded from the newly-picked chat in Customize
        scanPct = 0
        createPct = 0
        go(to: 3)
    }

    /// When entering Customize, seed the name field from the chat if empty.
    func seedNameIfNeeded() {
        if name.isEmpty { name = selectedChatName }
    }
}
