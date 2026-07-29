import Foundation

struct SyncOutcome: Sendable, Equatable {
    let playlistName: String
    let added: Int
    let skippedReason: String?
}

struct PlaylistSync {
    let messages: MessagesReading
    let spotify: SpotifyProviding
    let persistence: PersistenceProviding
    let status: SyncStatus
    @discardableResult
    func syncAll() async -> [SyncOutcome] {
        await status.begin()

        // A corrupt store must abort; treating it as empty would re-add every track.
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
                // Commit each batch so a mid-run 5xx preserves landed tracks without re-adding them.
                let added = try await spotify.appendTracks(playlistID: playlist.spotifyID, trackURIs: new) { batch in
                    persistence.recordSeen(spotifyID: playlist.spotifyID, uris: batch)
                }
                reconcileSongCount(playlist)
                outcomes.append(synced(playlist, added: added))
            } catch SpotifyError.needsReconnect(let reason) {
                needsReconnect = true
                reconnectReason = reason
                outcomes.append(skip(playlist, "reconnect Spotify"))
                break
            } catch SpotifyError.playlistPublic {
                outcomes.append(skip(playlist, "playlist is public"))
            } catch SpotifyError.playlistFull {
                outcomes.append(skip(playlist, "playlist full"))
            } catch {
                reconcileSongCount(playlist)
                outcomes.append(skip(playlist, "temporary error, will retry"))
            }
        }

        await status.complete(outcomes: outcomes, needsReconnect: needsReconnect, reconnectReason: reconnectReason)
        return outcomes
    }

    // MARK: - Reconcile

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
