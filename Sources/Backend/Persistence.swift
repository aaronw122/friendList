import Foundation

/// A playlist we created, persisted so Home survives quit. `externalURL` is the
/// Spotify web URL (populated in M2; empty until then).
struct SavedPlaylist: Codable, Hashable {
    var spotifyID: String        // Spotify playlist id (empty until M2 writes it)
    var name: String
    var songCount: Int
    var chatName: String
    var chatGUID: String
    var externalURL: String
}

/// Small UserDefaults/Application-Support-backed store for the durable bits the
/// plan (C2) requires: the FDA relaunch-resume marker, an onboarding-complete
/// flag, the created playlists (Home), and the per-chat dedup seen-set (M2).
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
    static func loadPlaylists() -> [SavedPlaylist] {
        guard let data = defaults.data(forKey: kPlaylists),
              let list = try? JSONDecoder().decode([SavedPlaylist].self, from: data)
        else { return [] }
        return list
    }
    static func savePlaylists(_ list: [SavedPlaylist]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: kPlaylists)
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
