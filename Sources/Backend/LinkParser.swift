import Foundation

/// Extracts Spotify track ids (and counts YouTube links) from raw message text
/// and from `attributedBody` / `payload_data` blobs.
///
/// The blob path is deliberately a **byte-scan**, per the tribunal ruling: the
/// `attributedBody` blob is a non-keyed `streamtyped` archive that
/// `NSAttributedString(data:documentAttributes:)` cannot decode. But any URL
/// inside it is a contiguous ASCII run, and a lossy UTF-8 decode
/// (`String(decoding:as:)`, which maps invalid bytes to U+FFFD) can never
/// corrupt an all-ASCII `https://open.spotify.com/track/…` or `spotify:track:…`
/// substring — so a regex over the decoded text finds them reliably and is
/// robust across macOS versions.
protocol LinkParsing: Sendable {
    /// Canonical `spotify:track:{id}` URIs found, in order, with duplicates kept
    /// (dedup happens per-chat upstream).
    func spotifyTrackURIs(in text: String) -> [String]
    /// Number of YouTube video links (counted, not collected — v2 feature).
    func youTubeCount(in text: String) -> Int
    /// Lossily decode a blob to text for scanning.
    func decode(blob: Data) -> String
}

struct LinkParser: LinkParsing {
    // Spotify track ids are 22 base62 chars. Allow the `/intl-xx/` locale prefix
    // and ignore any `?si=` query. Both the open.spotify.com URL and the
    // `spotify:track:` URI forms are matched.
    private static let spotifyURL = try! NSRegularExpression(
        pattern: #"open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]{22})"#,
        options: [.caseInsensitive])
    private static let spotifyURI = try! NSRegularExpression(
        pattern: #"spotify:track:([A-Za-z0-9]{22})"#,
        options: [.caseInsensitive])
    private static let youtube = try! NSRegularExpression(
        pattern: #"(?:youtube\.com/watch\?[^\s]*\bv=|youtu\.be/)([A-Za-z0-9_-]{11})"#,
        options: [.caseInsensitive])

    func spotifyTrackURIs(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var ids: [String] = []
        for re in [Self.spotifyURL, Self.spotifyURI] {
            re.enumerateMatches(in: text, range: range) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                ids.append(ns.substring(with: m.range(at: 1)))
            }
        }
        return ids.map { "spotify:track:\($0)" }
    }

    func youTubeCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return Self.youtube.numberOfMatches(in: text, range: range)
    }

    func decode(blob: Data) -> String {
        String(decoding: blob, as: UTF8.self)
    }
}
