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
    var authorizationDate: Date? { get set }
    func loadPlaylists() -> [SavedPlaylist]?
    func upsertPlaylists(_ updates: [SavedPlaylist])
    func recordSeen(spotifyID: String, uris: [String])
    func seen(forSpotifyID id: String) -> Set<String>
}

struct AppPersistence: PersistenceProviding {
    var didOnboard: Bool {
        get { Persistence.didOnboard }
        nonmutating set { Persistence.didOnboard = newValue }
    }

    var authorizationDate: Date? {
        get { Persistence.authorizationDate }
        nonmutating set { Persistence.authorizationDate = newValue }
    }

    func loadPlaylists() -> [SavedPlaylist]? { Persistence.loadPlaylists() }
    func upsertPlaylists(_ updates: [SavedPlaylist]) { Persistence.upsertPlaylists(updates) }
    func recordSeen(spotifyID: String, uris: [String]) { Persistence.recordSeen(spotifyID: spotifyID, uris: uris) }
    func seen(forSpotifyID id: String) -> Set<String> { Persistence.seen(forSpotifyID: id) }
}

struct StoreFile: Codable {
    var schemaVersion: Int
    var seen: [String: [String]]
    var playlists: [SavedPlaylist]
    var authorizationDate: Date?
}

enum Persistence {
    private static let defaults = UserDefaults.standard
    private static let fm = FileManager.default
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let schemaVersion = 1

    static var storeDirectoryOverride: URL?

    // MARK: Onboarding complete
    private static let kDidOnboard = "friendlist.didOnboard"
    static var didOnboard: Bool {
        get { defaults.bool(forKey: kDidOnboard) }
        set { defaults.set(newValue, forKey: kDidOnboard) }
    }

    // MARK: File store locations
    private static var storeDir: URL {
        if let override = storeDirectoryOverride { return override }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("com.friendlist.app", isDirectory: true)
    }
    private static var storeURL: URL { storeDir.appendingPathComponent("store.json") }
    private static var backupURL: URL { storeDir.appendingPathComponent("store.json.bak") }
    private static var corruptURL: URL { storeDir.appendingPathComponent("store.json.corrupt") }

    private static func ensureDir() {
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
    }

    private static let storeMutex = NSRecursiveLock()

    // MARK: Playlists
    static func loadPlaylists() -> [SavedPlaylist]? { currentStore()?.playlists }

    static func upsertPlaylists(_ updates: [SavedPlaylist]) {
        guard !updates.isEmpty else { return }
        mutateStore { store in
            for update in updates {
                if let index = store.playlists.firstIndex(where: { playlistsMatch($0, update) }) {
                    store.playlists[index] = update
                } else {
                    store.playlists.append(update)
                }
            }
        }
    }

    private static func playlistsMatch(_ lhs: SavedPlaylist, _ rhs: SavedPlaylist) -> Bool {
        if !rhs.spotifyID.isEmpty { return lhs.spotifyID == rhs.spotifyID }
        return lhs.name == rhs.name && lhs.chatGUID == rhs.chatGUID
    }

    // MARK: Dedup seen-set (keyed by spotifyID so two playlists from one chat track apart)
    static func seen(forSpotifyID id: String) -> Set<String> {
        guard let store = currentStore() else { return [] }
        return Set(store.seen[id] ?? [])
    }

    static func recordSeen(spotifyID: String, uris: [String]) {
        guard !spotifyID.isEmpty else { return }
        mutateStore { store in
            var set = Set(store.seen[spotifyID] ?? [])
            set.formUnion(uris)
            store.seen[spotifyID] = Array(set)
        }
    }

    // MARK: Spotify authorization date (drives the 6-month token-expiry nudge)
    static var authorizationDate: Date? {
        get { currentStore()?.authorizationDate }
        set { mutateStore { $0.authorizationDate = newValue } }
    }

    // MARK: Store read/write core
    // A corrupt store aborts mutation so existing bytes and dedup state are never wiped.
    @discardableResult
    static func mutateStore<T>(_ body: (inout StoreFile) -> T) -> T? {
        storeMutex.lock()
        defer { storeMutex.unlock() }
        guard var store = loadOrCreateLocked() else { return nil }
        let result = body(&store)
        writeStore(store)
        return result
    }

    private static func currentStore() -> StoreFile? {
        switch readStoreRaw() {
        case .decoded(let store):
            return store
        case .corrupt(let raw):
            stashCorrupt(raw)
            return nil
        case .fresh:
            storeMutex.lock()
            defer { storeMutex.unlock() }
            return loadOrCreateLocked()
        }
    }

    private enum StoreRead {
        case fresh
        case decoded(StoreFile)
        case corrupt(Data)
    }

    private static func readStoreRaw() -> StoreRead {
        ensureDir()
        guard fm.fileExists(atPath: storeURL.path) else { return .fresh }
        guard let data = try? Data(contentsOf: storeURL) else { return .corrupt(Data()) }
        guard let store = try? decoder.decode(StoreFile.self, from: data) else { return .corrupt(data) }
        return .decoded(store)
    }

    private static func loadOrCreateLocked() -> StoreFile? {
        switch readStoreRaw() {
        case .decoded(let store):
            return store
        case .corrupt(let raw):
            stashCorrupt(raw)
            return nil
        case .fresh:
            let built = StoreFile(schemaVersion: schemaVersion, seen: [:], playlists: [], authorizationDate: nil)
            writeStore(built)
            return built
        }
    }

    private static func writeStore(_ store: StoreFile) {
        ensureDir()
        if fm.fileExists(atPath: storeURL.path), let current = try? Data(contentsOf: storeURL) {
            try? current.write(to: backupURL, options: .atomic)
        }
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func stashCorrupt(_ raw: Data) {
        ensureDir()
        try? raw.write(to: corruptURL, options: .atomic)
    }
}
