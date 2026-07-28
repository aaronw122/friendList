import Foundation

struct SavedPlaylist: Codable, Hashable {
    var spotifyID: String
    var name: String
    var songCount: Int
    var chatName: String
    var chatGUID: String
    var externalURL: String
}

protocol PersistenceProviding {
    var didOnboard: Bool { get set }
    func loadPlaylists() -> [SavedPlaylist]?
    func upsertPlaylists(_ updates: [SavedPlaylist])
    func recordSeen(chatGUID: String, uris: [String])
}

struct AppPersistence: PersistenceProviding {
    var didOnboard: Bool {
        get { Persistence.didOnboard }
        nonmutating set { Persistence.didOnboard = newValue }
    }

    func loadPlaylists() -> [SavedPlaylist]? { Persistence.loadPlaylists() }
    func upsertPlaylists(_ updates: [SavedPlaylist]) { Persistence.upsertPlaylists(updates) }
    func recordSeen(chatGUID: String, uris: [String]) { Persistence.recordSeen(chatGUID: chatGUID, uris: uris) }
}

enum Persistence {
    private static let defaults = UserDefaults.standard

    // MARK: FDA relaunch resume
    private static let kResumeAtPicker = "friendlist.resumeAtPicker"
    static var resumeAtPicker: Bool {
        get { defaults.bool(forKey: kResumeAtPicker) }
        set { defaults.set(newValue, forKey: kResumeAtPicker) }
    }

    // MARK: Onboarding complete
    private static let kDidOnboard = "friendlist.didOnboard"
    static var didOnboard: Bool {
        get { defaults.bool(forKey: kDidOnboard) }
        set { defaults.set(newValue, forKey: kDidOnboard) }
    }

    // MARK: Created playlists (Home)
    private static let kPlaylists = "friendlist.playlists"
    private static let kPlaylistsBackup = "friendlist.playlists.bak"
    private static let kPlaylistsCorrupt = "friendlist.playlists.corrupt"

    static func loadPlaylists() -> [SavedPlaylist]? {
        switch playlistStore() {
        case .absent:
            return []
        case .loaded(let list):
            return list
        case .undecodable(let raw):
            defaults.set(raw, forKey: kPlaylistsCorrupt)
            return nil
        }
    }

    static func upsertPlaylists(_ updates: [SavedPlaylist]) {
        guard !updates.isEmpty else { return }

        let stored = playlistStore()
        var list: [SavedPlaylist]
        switch stored {
        case .absent:
            list = []
        case .loaded(let current):
            list = current
        case .undecodable(let raw):
            defaults.set(raw, forKey: kPlaylistsCorrupt)
            list = []
        }

        for update in updates {
            if let index = list.firstIndex(where: { playlistsMatch($0, update) }) {
                list[index] = update
            } else {
                list.append(update)
            }
        }

        guard let data = try? JSONEncoder().encode(list) else { return }
        if let prior = defaults.object(forKey: kPlaylists) {
            defaults.set(prior, forKey: kPlaylistsBackup)
        }
        defaults.set(data, forKey: kPlaylists)
    }

    private enum PlaylistStore {
        case absent
        case loaded([SavedPlaylist])
        case undecodable(Any)
    }

    private static func playlistStore() -> PlaylistStore {
        guard let raw = defaults.object(forKey: kPlaylists) else { return .absent }
        guard let data = raw as? Data,
              let list = try? JSONDecoder().decode([SavedPlaylist].self, from: data)
        else { return .undecodable(raw) }
        return .loaded(list)
    }

    private static func playlistsMatch(_ lhs: SavedPlaylist, _ rhs: SavedPlaylist) -> Bool {
        if !rhs.spotifyID.isEmpty { return lhs.spotifyID == rhs.spotifyID }
        return lhs.name == rhs.name && lhs.chatGUID == rhs.chatGUID
    }

    // MARK: Per-chat dedup seen-set (M2 in-app dedup)
    private static let kSeen = "friendlist.seen"
    static func seenTracks(chatGUID: String) -> Set<String> {
        let all = seenMap()
        return Set(all[chatGUID] ?? [])
    }
    static func recordSeen(chatGUID: String, uris: [String]) {
        var all = seenMap()
        var set = Set(all[chatGUID] ?? [])
        set.formUnion(uris)
        all[chatGUID] = Array(set)
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: kSeen) }
    }
    private static func seenMap() -> [String: [String]] {
        guard let data = defaults.data(forKey: kSeen),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return map
    }
}
