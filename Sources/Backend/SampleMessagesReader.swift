import Foundation

struct SampleMessagesReader: MessagesReading {
    var grantsAccess: Bool = true

    private static let samples: [(String, Int)] = [
        ("the boys", 48), ("Cabin Trip 2026", 12), ("brunch club", 31),
        ("Design crew", 21), ("roommates", 9), ("Fam", 3),
        ("sunday runners", 6), ("SF 2025", 17), ("climbing gym", 8),
        ("college", 27), ("book club", 4), ("neighbors", 2),
    ]

    func canRead() -> Bool { grantsAccess }

    func groupChats() throws -> [GroupChat] {
        Self.samples.enumerated().map { i, s in
            GroupChat(guid: "sample-\(i)", name: s.0, messageCount: s.1 * 40,
                      lastDate: Int64(1_000_000 - i), linkCount: s.1)
        }
    }

    func scan(chatGUID: String, progress: @escaping (ScanProgress) -> Void) throws -> ChatScan {
        let idx = Int(chatGUID.split(separator: "-").last.flatMap { Int($0) } ?? 0)
        let n = Self.samples.indices.contains(idx) ? Self.samples[idx].1 : 12
        let uris = (0..<n).map { "spotify:track:\(String(format: "%022d", $0))" }
        progress(ScanProgress(fraction: 1, messagesScanned: n * 40, found: uris.count, label: "Found \(uris.count) songs"))
        return ChatScan(trackURIs: uris, youtubeCount: 0, spotifyShortLinkCount: 0, messagesScanned: n * 40)
    }
}
