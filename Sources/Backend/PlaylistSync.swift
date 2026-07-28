import Foundation

// Result for one playlist in a run; skippedReason == nil means it synced (added may be 0).
struct SyncOutcome: Sendable, Equatable {
    let playlistName: String
    let added: Int
    let skippedReason: String?
}

// UI-free sync core shared by the in-app run and the headless agent. Depends only on the
// messaging, Spotify, and Persistence abstractions — no SwiftUI. A whole run holds one
// cross-process advisory lock (spanning the Spotify token refresh) so the GUI and headless
// processes never both spend the single-use rotating refresh token; every read of
// seen/playlists happens fresh inside that lock.
struct PlaylistSync {
    // How the caller wants the lock acquired.
    enum Trigger {
        case background     // launch/background: skip immediately if another run holds the lock
        case userInitiated  // "Sync now": wait up to the budget, then report already-running
    }

    let messages: MessagesReading
    let spotify: SpotifyProviding
    let persistence: PersistenceProviding
    let status: SyncStatus
    // Bounded-blocking budget for userInitiated; small and injectable so tests stay fast.
    var busyWait: TimeInterval = 3
    var busyPoll: TimeInterval = 0.1

    @discardableResult
    func syncAll(trigger: Trigger) async -> [SyncOutcome] {
        guard await acquireLock(trigger: trigger) else {
            if trigger == .userInitiated { await status.reportAlreadyRunning() }
            return []
        }
        defer { persistence.releaseSyncLock() }
        await status.begin()

        // A nil load means a corrupt/torn store: abort rather than proceed on empty seen
        // (which would re-add every track). The store layer preserves the bad bytes.
        guard let playlists = persistence.loadPlaylists() else {
            await status.fail("Sync store unreadable")
            return []
        }

        var outcomes: [SyncOutcome] = []
        var needsReconnect = false
        var reconnectReason: ReconnectReason?

        for playlist in playlists {
            guard !playlist.spotifyID.isEmpty, !playlist.chatGUID.isEmpty else { continue }

            guard messages.canRead() else {
                outcomes.append(skip(playlist, "no Full Disk Access"))
                continue
            }

            let scanned: [String]
            do {
                scanned = try messages.scan(chatGUID: playlist.chatGUID, progress: { _ in }).trackURIs
            } catch {
                // Transient read failure (db busy): skip and retry next run.
                outcomes.append(skip(playlist, "couldn't read chat"))
                continue
            }

            let seen = persistence.seen(forSpotifyID: playlist.spotifyID)
            let new = scanned.filter { !seen.contains($0) }
            if new.isEmpty {
                outcomes.append(synced(playlist, added: 0))
                continue
            }

            do {
                // Commit each landed batch to seen immediately so a mid-run 5xx neither loses
                // landed tracks nor re-adds them next run.
                let added = try await spotify.appendTracks(playlistID: playlist.spotifyID, trackURIs: new) { batch in
                    persistence.recordSeen(spotifyID: playlist.spotifyID, uris: batch)
                }
                reconcileSongCount(playlist)
                outcomes.append(synced(playlist, added: added))
            } catch SpotifyError.needsReconnect(let reason) {
                // invalid_grant: token dead for every playlist this run; seen untouched, stop here.
                needsReconnect = true
                reconnectReason = reason
                outcomes.append(skip(playlist, "reconnect Spotify"))
                break
            } catch SpotifyError.playlistPublic {
                outcomes.append(skip(playlist, "playlist is public"))
            } catch SpotifyError.playlistFull {
                outcomes.append(skip(playlist, "playlist full"))
            } catch {
                // Transient 5xx/network: landed batches are already recorded; retry next run.
                reconcileSongCount(playlist)
                outcomes.append(skip(playlist, "temporary error, will retry"))
            }
        }

        await status.complete(outcomes: outcomes, needsReconnect: needsReconnect, reconnectReason: reconnectReason)
        return outcomes
    }

    // MARK: - Lock

    private func acquireLock(trigger: Trigger) async -> Bool {
        switch trigger {
        case .background:
            return persistence.acquireSyncLock(blocking: false)
        case .userInitiated:
            let deadline = Date().addingTimeInterval(busyWait)
            while true {
                if persistence.acquireSyncLock(blocking: false) { return true }
                if Date() >= deadline { return false }
                try? await Task.sleep(nanoseconds: UInt64(busyPoll * 1_000_000_000))
            }
        }
    }

    // MARK: - Reconcile

    // songCount == songs sent, derived from seen and merged into the playlists file via the
    // lock-guarded upsert (a fresh read-modify-write), so it survives a long-open GUI snapshot.
    private func reconcileSongCount(_ playlist: SavedPlaylist) {
        var updated = playlist
        updated.songCount = persistence.seen(forSpotifyID: playlist.spotifyID).count
        persistence.upsertPlaylists([updated])
    }

    private func synced(_ playlist: SavedPlaylist, added: Int) -> SyncOutcome {
        SyncOutcome(playlistName: playlist.name, added: added, skippedReason: nil)
    }

    private func skip(_ playlist: SavedPlaylist, _ reason: String) -> SyncOutcome {
        SyncOutcome(playlistName: playlist.name, added: 0, skippedReason: reason)
    }
}
