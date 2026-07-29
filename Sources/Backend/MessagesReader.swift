import Foundation

// MARK: - Models

struct GroupChat: Identifiable, Hashable {
    var id: String { guid }
    let guid: String
    let name: String
    let messageCount: Int
    let lastDate: Int64
    var linkCount: Int
}

struct ScanProgress {
    let fraction: Double
    let messagesScanned: Int
    let found: Int
    let label: String
}

struct ChatScan {
    let trackURIs: [String]
    let youtubeCount: Int
    var spotifyShortLinkCount: Int = 0
    let messagesScanned: Int
}

// MARK: - Seam

protocol MessagesReading: Sendable {
    func canRead() -> Bool
    func groupChats() throws -> [GroupChat]
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

    private static let linkCountRecentWindow: Int64 = 40_000

    func canRead() -> Bool {
        do {
            let db = try SQLiteReadOnly(path: dbPath)
            try db.query("SELECT 1 FROM chat LIMIT 1") { _ in }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Sibling merge

    /// One chat row per transport; rows sharing `chat_identifier` are the same conversation.
    struct ChatRow {
        let rowid: Int64
        let guid: String
        let identifier: String
        let display: String
        let msgCount: Int
        let last: Int64
    }

    struct MergedChat {
        let canonical: ChatRow
        let rowIDs: [Int64]
        let display: String
        let msgCount: Int
        let last: Int64
    }

    /// Groups transport siblings into one logical chat; the iMessage guid wins canonically (then lexicographic) so persistence keys stay stable.
    static func mergeSiblings(_ rows: [ChatRow]) -> [MergedChat] {
        var order: [String] = []
        var groups: [String: [ChatRow]] = [:]
        for row in rows {
            let key = row.identifier.isEmpty ? row.guid : row.identifier
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { key in
            let siblings = groups[key]!
            let canonical = siblings.min { a, b in
                (a.guid.hasPrefix("iMessage;") ? 0 : 1, a.guid) < (b.guid.hasPrefix("iMessage;") ? 0 : 1, b.guid)
            }!
            let display = canonical.display.isEmpty
                ? (siblings.first(where: { !$0.display.isEmpty })?.display ?? "")
                : canonical.display
            return MergedChat(canonical: canonical,
                              rowIDs: siblings.map(\.rowid),
                              display: display,
                              msgCount: siblings.reduce(0) { $0 + $1.msgCount },
                              last: siblings.map(\.last).max() ?? 0)
        }
    }

    func groupChats() throws -> [GroupChat] {
        let db = try SQLiteReadOnly(path: dbPath)

        let sql = """
        SELECT c.ROWID,
               c.guid,
               COALESCE(c.chat_identifier, '') AS chat_identifier,
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

        var rows: [ChatRow] = []
        try db.query(sql) { row in
            let guid = row.text(1) ?? ""
            guard !guid.isEmpty else { return }
            rows.append(ChatRow(rowid: row.int(0),
                                guid: guid,
                                identifier: row.text(2) ?? "",
                                display: row.text(3) ?? "",
                                msgCount: Int(row.int(5)),
                                last: row.int(6)))
        }

        let merged = Self.mergeSiblings(rows).sorted { $0.last > $1.last }

        var names: [Int64: String] = [:]
        for chat in merged where chat.display.isEmpty {
            names[chat.canonical.rowid] = try participantName(chatRowID: chat.canonical.rowid, db: db)
        }

        let recentURIs = try recentLinkURIs(db: db)

        return merged.map { chat in
            let uris = chat.rowIDs.reduce(into: Set<String>()) { $0.formUnion(recentURIs[$1] ?? []) }
            return GroupChat(guid: chat.canonical.guid,
                             name: chat.display.isEmpty ? (names[chat.canonical.rowid] ?? "Group chat") : chat.display,
                             messageCount: chat.msgCount,
                             lastDate: chat.last,
                             linkCount: uris.count)
        }
    }

    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        let db = try SQLiteReadOnly(path: dbPath)

        let rowIDs = try siblingRowIDs(chatGUID: chatGUID, db: db)
        guard !rowIDs.isEmpty else {
            return ChatScan(trackURIs: [], youtubeCount: 0, spotifyShortLinkCount: 0, messagesScanned: 0)
        }
        // ROWIDs come from our own query above, so interpolation is injection-safe.
        let idList = rowIDs.map(String.init).joined(separator: ",")
        var total = 0
        try db.query("SELECT COUNT(DISTINCT message_id) FROM chat_message_join WHERE chat_id IN (\(idList))") { row in
            total = Int(row.int(0))
        }

        let sql = """
        SELECT m.ROWID, m.text, m.attributedBody, m.payload_data
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE cmj.chat_id IN (\(idList))
        GROUP BY m.ROWID
        ORDER BY m.ROWID ASC
        """

        var ordered: [String] = []
        var seen = Set<String>()
        var youtube = 0
        var shortLinks = 0
        var scanned = 0

        try db.query(sql) { row in
            scanned += 1
            let haystack = combinedText(row: row)
            for uri in parser.spotifyTrackURIs(in: haystack) where !seen.contains(uri) {
                seen.insert(uri)
                ordered.append(uri)
            }
            youtube += parser.youTubeCount(in: haystack)
            shortLinks += parser.spotifyShortLinkCount(in: haystack)

            if scanned % 250 == 0 {
                let frac = total > 0 ? min(0.98, Double(scanned) / Double(total)) : 0.5
                progress(ScanProgress(fraction: frac,
                                      messagesScanned: scanned,
                                      found: ordered.count,
                                      label: "Scanning \(scanned) of \(total) messages…"))
            }
        }

        return ChatScan(trackURIs: ordered,
                        youtubeCount: youtube,
                        spotifyShortLinkCount: shortLinks,
                        messagesScanned: scanned)
    }

    // MARK: - Helpers

    /// Resolves every transport sibling of the chat so a scan reads the whole conversation.
    private func siblingRowIDs(chatGUID: String, db: SQLiteReadOnly) throws -> [Int64] {
        var rowid: Int64?
        var identifier = ""
        try db.query("SELECT ROWID, COALESCE(chat_identifier, '') FROM chat WHERE guid = ? LIMIT 1",
                     [.text(chatGUID)]) { row in
            rowid = row.int(0)
            identifier = row.text(1) ?? ""
        }
        guard let rowid else { return [] }
        guard !identifier.isEmpty else { return [rowid] }
        var ids: [Int64] = []
        try db.query("SELECT ROWID FROM chat WHERE chat_identifier = ? ORDER BY ROWID ASC",
                     [.text(identifier)]) { row in
            ids.append(row.int(0))
        }
        return ids.isEmpty ? [rowid] : ids
    }

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

    /// Per-chat-row URI sets so callers can union across transport siblings before counting.
    private func recentLinkURIs(db: SQLiteReadOnly) throws -> [Int64: Set<String>] {
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
        return uris
    }

    private func combinedTextForCount(row: SQLiteRow) -> String {
        var parts: [String] = []
        if let t = row.text(1), !t.isEmpty { parts.append(t) }
        if let body = row.blob(2) { parts.append(parser.decode(blob: body)) }
        if let payload = row.blob(3) { parts.append(parser.decode(blob: payload)) }
        return parts.joined(separator: "\n")
    }
}
