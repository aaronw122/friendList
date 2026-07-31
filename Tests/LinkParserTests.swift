import XCTest
@testable import FriendList

final class LinkParserTests: XCTestCase {
    private let parser = LinkParser()
    private let id = "6rqhFgbbKwnb9MLmUQDhG6"

    // MARK: canonical track URLs

    func testHTTPSTrackURLWithQueryString() {
        let uris = parser.spotifyTrackURIs(in: "https://open.spotify.com/track/\(id)?si=abc123&context=share")
        XCTAssertEqual(uris, ["spotify:track:\(id)"])
    }

    func testHTTPAndSchemelessTrackURLs() {
        XCTAssertEqual(parser.spotifyTrackURIs(in: "http://open.spotify.com/track/\(id)"),
                       ["spotify:track:\(id)"])
        XCTAssertEqual(parser.spotifyTrackURIs(in: "check open.spotify.com/track/\(id) out"),
                       ["spotify:track:\(id)"])
    }

    func testLocalePrefixedTrackURL() {
        XCTAssertEqual(parser.spotifyTrackURIs(in: "https://open.spotify.com/intl-de/track/\(id)"),
                       ["spotify:track:\(id)"])
    }

    func testUppercaseTrackIDIsPreservedVerbatim() {
        let upper = "6RQHFGBBKWNB9MLMUQDHG6"
        XCTAssertEqual(parser.spotifyTrackURIs(in: "https://open.spotify.com/track/\(upper)"),
                       ["spotify:track:\(upper)"])
    }

    func testTrailingPunctuationIsExcludedFromID() {
        XCTAssertEqual(parser.spotifyTrackURIs(in: "listen! https://open.spotify.com/track/\(id)."),
                       ["spotify:track:\(id)"])
        XCTAssertEqual(parser.spotifyTrackURIs(in: "(https://open.spotify.com/track/\(id))"),
                       ["spotify:track:\(id)"])
    }

    // MARK: spotify:track: URIs

    func testSpotifyTrackURI() {
        XCTAssertEqual(parser.spotifyTrackURIs(in: "queue spotify:track:\(id) next"),
                       ["spotify:track:\(id)"])
    }

    // MARK: rejections

    func testNonTrackLinksAreRejected() {
        let text = """
        https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3
        https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
        https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF
        spotify:album:1DFixLWuPkv3KT3TnV35m3
        """
        XCTAssertTrue(parser.spotifyTrackURIs(in: text).isEmpty)
    }

    func testTooShortIDAndEmptyTextAreRejected() {
        XCTAssertTrue(parser.spotifyTrackURIs(in: "https://open.spotify.com/track/tooShort123").isEmpty)
        XCTAssertTrue(parser.spotifyTrackURIs(in: "").isEmpty)
    }

    // MARK: duplicates

    func testDuplicatesArePreservedForCallerSideDedup() {
        let text = "https://open.spotify.com/track/\(id) again https://open.spotify.com/track/\(id) spotify:track:\(id)"
        XCTAssertEqual(parser.spotifyTrackURIs(in: text),
                       Array(repeating: "spotify:track:\(id)", count: 3))
    }

    // MARK: spotify.link short links

    func testShortLinkVariantsAreCounted() {
        XCTAssertEqual(parser.spotifyShortLinkCount(in: "listen https://spotify.link/AbC123xyz and also spotify.link/ZZ99"), 2)
        XCTAssertEqual(parser.spotifyShortLinkCount(in: "SPOTIFY.LINK/AbC123"), 1)
        XCTAssertEqual(parser.spotifyShortLinkCount(in: "https://spotify.link/AbC123?si=xyz"), 1)
    }

    func testFullURLsMissingSlugsAndEmptyTextAreNotCounted() {
        XCTAssertEqual(parser.spotifyShortLinkCount(in: "https://open.spotify.com/track/\(id)"), 0)
        XCTAssertEqual(parser.spotifyShortLinkCount(in: "https://spotify.link/ and nothing after"), 0)
        XCTAssertEqual(parser.spotifyShortLinkCount(in: ""), 0)
    }

    func testShortLinksAreNotReturnedAsTrackURIs() {
        XCTAssertTrue(parser.spotifyTrackURIs(in: "https://spotify.link/AbC123xyz").isEmpty)
    }
}
