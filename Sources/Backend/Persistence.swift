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

// The cross-process state lives in one JSON file under Application Support: `seen`
// (dedup map keyed by spotifyID) and the created playlists. Reads are lock-free
// (atomic rename means no torn read); every write funnels through `mutateStore`
// under a dedicated advisory `sync.lock`, so the GUI and headless agent never
// clobber each other. A decode failure aborts rather than wiping good data.
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

    // Test seams: point the store at a temp dir and feed migration a scratch defaults.
    static var storeDirectoryOverride: URL?
    static var legacyDefaults: UserDefaults = .standard

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
    static var lockURL: URL { storeDir.appendingPathComponent("sync.lock") }

    private static func ensureDir() {
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
    }

    // MARK: Cross-process advisory lock
    // The reusable primitive the sync core wraps around an entire run. Non-blocking
    // acquire skips when another process is active; the bounded blocking variant is
    // for the user-initiated "Sync now". Reentrant within a process so the mutate
    // helpers can re-enter the lock the sync core already holds without deadlocking.
    @discardableResult
    static func withSyncLock<T>(blocking: Bool, _ body: () throws -> T) rethrows -> T? {
        guard SyncLock.shared.acquire(blocking: blocking) else { return nil }
        defer { SyncLock.shared.release() }
        return try body()
    }

    @discardableResult
    static func acquireSyncLock(blocking: Bool) -> Bool { SyncLock.shared.acquire(blocking: blocking) }
    static func releaseSyncLock() { SyncLock.shared.release() }

    // MARK: Playlists
    static func loadPlaylists() -> [SavedPlaylist]? { currentStore()?.playlists }

    // The single writer path for the playlists file, carrying PR #8's upsert-by-
    // spotifyID merge (name+chatGUID fallback) forward under the lock.
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
    // Lock-guarded read-fresh → mutate → write. Returns nil on a corrupt store
    // (mutation aborted, good bytes preserved) rather than wiping seen/playlists.
    @discardableResult
    static func mutateStore<T>(_ body: (inout StoreFile) -> T) -> T? {
        withSyncLock(blocking: true) { () -> T? in
            guard var store = loadOrMigrateLocked() else { return nil }
            let result = body(&store)
            writeStore(store)
            return result
        }.flatMap { $0 }
    }

    private static func currentStore() -> StoreFile? {
        switch readStoreRaw() {
        case .decoded(let store):
            return store
        case .corrupt(let raw):
            stashCorrupt(raw)
            return nil
        case .fresh:
            return withSyncLock(blocking: true) { loadOrMigrateLocked() }.flatMap { $0 }
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

    // Must run under the lock: materializes the file on first-ever access (one-time
    // migration from the legacy UserDefaults `seen`/`playlists`), nil == corrupt.
    private static func loadOrMigrateLocked() -> StoreFile? {
        switch readStoreRaw() {
        case .decoded(let store):
            return store
        case .corrupt(let raw):
            stashCorrupt(raw)
            return nil
        case .fresh:
            let built = migrateFromLegacy()
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

    // MARK: One-time migration (chatGUID-keyed UserDefaults → spotifyID-keyed file)
    private static let kPlaylists = "friendlist.playlists"
    private static let kPlaylistsCorrupt = "friendlist.playlists.corrupt"
    private static let kSeen = "friendlist.seen"

    private static func migrateFromLegacy() -> StoreFile {
        let playlists = legacyPlaylists()
        let legacySeen = legacySeenMap()
        var seen: [String: [String]] = [:]
        for playlist in playlists where !playlist.spotifyID.isEmpty {
            guard let uris = legacySeen[playlist.chatGUID] else { continue }
            var set = Set(seen[playlist.spotifyID] ?? [])
            set.formUnion(uris)
            seen[playlist.spotifyID] = Array(set)
        }
        return StoreFile(schemaVersion: schemaVersion, seen: seen, playlists: playlists, authorizationDate: nil)
    }

    private static func legacyPlaylists() -> [SavedPlaylist] {
        guard let raw = legacyDefaults.object(forKey: kPlaylists) else { return [] }
        guard let data = raw as? Data,
              let list = try? decoder.decode([SavedPlaylist].self, from: data)
        else {
            legacyDefaults.set(raw, forKey: kPlaylistsCorrupt)
            return []
        }
        return list
    }

    private static func legacySeenMap() -> [String: [String]] {
        guard let data = legacyDefaults.data(forKey: kSeen),
              let map = try? decoder.decode([String: [String]].self, from: data)
        else { return [:] }
        return map
    }
}

// Advisory `flock` on a dedicated file, reentrant within the process. The recursive
// mutex serializes in-process callers; `flock` excludes other processes. Depth tracks
// the single held fd so nested acquires reuse it instead of deadlocking on a fresh one.
private final class SyncLock {
    static let shared = SyncLock()
    private let mutex = NSRecursiveLock()
    private var fd: Int32 = -1
    private var depth = 0

    func acquire(blocking: Bool) -> Bool {
        mutex.lock()
        if depth > 0 {
            depth += 1
            return true
        }
        try? FileManager.default.createDirectory(at: Persistence.lockURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let handle = open(Persistence.lockURL.path, O_RDONLY | O_CREAT, 0o644)
        guard handle >= 0 else {
            mutex.unlock()
            return false
        }
        let operation = LOCK_EX | (blocking ? 0 : LOCK_NB)
        guard flock(handle, operation) == 0 else {
            close(handle)
            mutex.unlock()
            return false
        }
        fd = handle
        depth = 1
        return true
    }

    func release() {
        guard depth > 0 else {
            mutex.unlock()
            return
        }
        depth -= 1
        if depth == 0 {
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
        mutex.unlock()
    }
}
