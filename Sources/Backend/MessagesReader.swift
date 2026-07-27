import Foundation

// MARK: - Models

/// A group conversation surfaced to the picker.
struct GroupChat: Identifiable, Hashable {
    var id: String { guid }
    let guid: String
    let name: String
    let messageCount: Int
    let lastDate: Int64
    var linkCount: Int
}

/// Live progress while scanning one chat's history.
struct ScanProgress {
    let fraction: Double
    let messagesScanned: Int
    let found: Int
    let label: String
}

/// Result of scanning one chat: de-duplicated track URIs in send order.
struct ChatScan {
    let trackURIs: [String]   // ordered, unique (in-app dedup applied)
    let youtubeCount: Int
    let messagesScanned: Int
}

// MARK: - Seam

/// M1 read surface. Sendable so a scan can run off the main actor.
protocol MessagesReading: Sendable {
    /// Cheap probe: can we actually read chat.db right now (Full Disk Access)?
    func canRead() -> Bool
    /// Group chats for the picker, recency-sorted, with an approximate link count.
    func groupChats() throws -> [GroupChat]
    /// Full-history scan of one chat, extracting unique Spotify track URIs.
    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan
}

// MARK: - Real reader

struct MessagesReader: MessagesReading {
    let dbPath: String
    let parser: LinkParsing

    init(dbPath: String = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath,
         parser: LinkParsing = LinkParser()) {
        self.dbPath = dbPath
        self.parser = parser
    }

    // Bound the picker's approximate link count to the most recent messages so
    // it stays fast on large libraries. The exact per-chat scan runs later.
    private static let linkCountRecentWindow: Int64 = 40_000

    func canRead() -> Bool {
        do {
            let db = try SQLiteReadOnly(path: dbPath)
            // Success = the query prepared and stepped without throwing. Do NOT
            // require a row: a readable-but-empty `chat` table is still access.
            try db.query("SELECT 1 FROM chat LIMIT 1") { _ in }
            return true
        } catch {
            return false
        }
    }

    func groupChats() throws -> [GroupChat] {
        let db = try SQLiteReadOnly(path: dbPath)

        // Group detection, ordered per the canonical imessage-exporter approach:
        // primary = participant count > 1; trusted secondary = style 43; the
        // per-chat scalar subqueries avoid the join fan-out that would inflate
        // counts. A group decayed to a single participant can slip through as a
        // DM under the strict > 1 test — acceptable edge (style=43 recovers most).
        let sql = """
        SELECT c.ROWID,
               c.guid,
               COALESCE(c.display_name, '') AS display_name,
               (SELECT COUNT(*) FROM chat_handle_join chj WHERE chj.chat_id = c.ROWID) AS participants,
               (SELECT COUNT(*) FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID) AS msg_count,
               (SELECT MAX(m.date) FROM chat_message_join cmj
                  JOIN message m ON m.ROWID = cmj.message_id
                  WHERE cmj.chat_id = c.ROWID) AS last_date
        FROM chat c
        WHERE (SELECT COUNT(*) FROM chat_handle_join chj WHERE chj.chat_id = c.ROWID) > 1
           OR c.style = 43
        ORDER BY last_date DESC
        """

        struct Raw { let rowid: Int64; let guid: String; let display: String; let msgCount: Int; let last: Int64 }
        var raws: [Raw] = []
        try db.query(sql) { row in
            let guid = row.text(1) ?? ""
            guard !guid.isEmpty else { return }
            raws.append(Raw(rowid: row.int(0),
                            guid: guid,
                            display: row.text(2) ?? "",
                            msgCount: Int(row.int(4)),
                            last: row.int(5)))
        }

        // Name fallback for group chats without a display name: build from handles.
        var names: [Int64: String] = [:]
        for raw in raws where raw.display.isEmpty {
            names[raw.rowid] = try participantName(chatRowID: raw.rowid, db: db)
        }

        // Approximate per-chat Spotify link counts over the recent-message window.
        let counts = try recentLinkCounts(db: db)

        return raws.map { raw in
            GroupChat(guid: raw.guid,
                      name: raw.display.isEmpty ? (names[raw.rowid] ?? "Group chat") : raw.display,
                      messageCount: raw.msgCount,
                      lastDate: raw.last,
                      linkCount: counts[raw.rowid] ?? 0)
        }
    }

    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        let db = try SQLiteReadOnly(path: dbPath)

        // Resolve guid -> chat rowid and total message count (for progress).
        var chatRowID: Int64?
        try db.query("SELECT ROWID FROM chat WHERE guid = ? LIMIT 1", [.text(chatGUID)]) { row in
            chatRowID = row.int(0)
        }
        guard let rowid = chatRowID else {
            return ChatScan(trackURIs: [], youtubeCount: 0, messagesScanned: 0)
        }
        var total = 0
        try db.query("SELECT COUNT(*) FROM chat_message_join WHERE chat_id = ?", [.int(rowid)]) { row in
            total = Int(row.int(0))
        }

        // A message can join multiple chats — GROUP BY m.ROWID collapses those.
        let sql = """
        SELECT m.ROWID, m.text, m.attributedBody, m.payload_data
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE cmj.chat_id = ?
        GROUP BY m.ROWID
        ORDER BY m.ROWID ASC
        """

        var ordered: [String] = []
        var seen = Set<String>()
        var youtube = 0
        var scanned = 0

        try db.query(sql, [.int(rowid)]) { row in
            scanned += 1
            let haystack = combinedText(row: row)
            for uri in parser.spotifyTrackURIs(in: haystack) where !seen.contains(uri) {
                seen.insert(uri)
                ordered.append(uri)
            }
            youtube += parser.youTubeCount(in: haystack)

            if scanned % 250 == 0 {
                let frac = total > 0 ? min(0.98, Double(scanned) / Double(total)) : 0.5
                progress(ScanProgress(fraction: frac,
                                      messagesScanned: scanned,
                                      found: ordered.count,
                                      label: "Scanning \(scanned) of \(total) messages…"))
            }
        }

        return ChatScan(trackURIs: ordered, youtubeCount: youtube, messagesScanned: scanned)
    }

    // MARK: - Helpers

    /// Concatenate the message's text column with lossy decodes of the
    /// attributedBody and payload_data blobs (URL-preview balloons store the URL
    /// in payload_data). Newlines keep runs from accidentally joining.
    private func combinedText(row: SQLiteRow) -> String {
        var parts: [String] = []
        if let t = row.text(1), !t.isEmpty { parts.append(t) }
        if let body = row.blob(2) { parts.append(parser.decode(blob: body)) }
        if let payload = row.blob(3) { parts.append(parser.decode(blob: payload)) }
        return parts.joined(separator: "\n")
    }

    private func participantName(chatRowID: Int64, db: SQLiteReadOnly) throws -> String {
        var handles: [String] = []
        try db.query("""
            SELECT h.id FROM chat_handle_join chj
            JOIN handle h ON h.ROWID = chj.handle_id
            WHERE chj.chat_id = ?
            ORDER BY h.ROWID ASC
            """, [.int(chatRowID)]) { row in
            if let id = row.text(0) { handles.append(id) }
        }
        guard !handles.isEmpty else { return "Group chat" }
        if handles.count <= 3 { return handles.joined(separator: ", ") }
        return "\(handles.prefix(2).joined(separator: ", ")) +\(handles.count - 2)"
    }

    /// One bounded pass over the most-recent messages, tallying which chats had
    /// at least one Spotify link per message. Approximate but fast.
    private func recentLinkCounts(db: SQLiteReadOnly) throws -> [Int64: Int] {
        // Count UNIQUE tracks per chat (same metric as `scan`), not raw
        // occurrences — otherwise a song reposted N times inflates the preview
        // to several times the real playlist size (e.g. 1,249 occurrences vs 273
        // unique songs). Still bounded to the recent-message window for speed, so
        // this is an estimate that can undercount a chat with lots of old history;
        // the result screen remains the source of truth for the actual count.
        var uris: [Int64: Set<String>] = [:]
        let sql = """
        SELECT cmj.chat_id, m.text, m.attributedBody, m.payload_data
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE m.ROWID > (SELECT MAX(ROWID) FROM message) - ?
        """
        try db.query(sql, [.int(Self.linkCountRecentWindow)]) { row in
            let chatID = row.int(0)
            let text = combinedTextForCount(row: row)
            for uri in parser.spotifyTrackURIs(in: text) {
                uris[chatID, default: []].insert(uri)
            }
        }
        return uris.mapValues(\.count)
    }

    // Column indices differ from `scan` (chat_id is at 0 here).
    private func combinedTextForCount(row: SQLiteRow) -> String {
        var parts: [String] = []
        if let t = row.text(1), !t.isEmpty { parts.append(t) }
        if let body = row.blob(2) { parts.append(parser.decode(blob: body)) }
        if let payload = row.blob(3) { parts.append(parser.decode(blob: payload)) }
        return parts.joined(separator: "\n")
    }
}
