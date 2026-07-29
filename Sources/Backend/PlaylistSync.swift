import Foundation

// Result for one playlist in a run; skippedReason == nil means it synced (added may be 0).
struct SyncOutcome: Sendable, Equatable {
    let playlistName: String
    let added: Int
    let skippedReason: String?
}

// UI-free sync core used by the headless agent.
struct PlaylistSync {
    let messages: MessagesReading
    let spotify: SpotifyProviding
    let persistence: PersistenceProviding
    let status: SyncStatus
    @discardableResult
    func syncAll() async -> [SyncOutcome] {
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

    // MARK: - Reconcile

    // songCount is derived from seen and merged into the playlists file.
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
