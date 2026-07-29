import Foundation

/// Lossy UTF-8 byte scanning preserves embedded ASCII URLs that streamtyped attributedBody archives cannot decode.
protocol LinkParsing: Sendable {
    func spotifyTrackURIs(in text: String) -> [String]
    func spotifyShortLinkCount(in text: String) -> Int
    func youTubeCount(in text: String) -> Int
    func decode(blob: Data) -> String
}

struct LinkParser: LinkParsing {
    // Spotify IDs are 22 base62 characters; match locale-prefixed URLs and spotify:track URIs.
    private static let spotifyURL = try! NSRegularExpression(
        pattern: #"open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]{22})"#,
        options: [.caseInsensitive])
    private static let spotifyURI = try! NSRegularExpression(
        pattern: #"spotify:track:([A-Za-z0-9]{22})"#,
        options: [.caseInsensitive])
    // spotify.link short links hide the track behind a redirect; counted for disclosure, never resolved.
    private static let spotifyShortLink = try! NSRegularExpression(
        pattern: #"spotify\.link/[A-Za-z0-9]+"#,
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

    func spotifyShortLinkCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return Self.spotifyShortLink.numberOfMatches(in: text, range: range)
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
