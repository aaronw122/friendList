import XCTest
import CryptoKit
@testable import FriendList

final class PKCETests: XCTestCase {
    // MARK: verifier shape

    func testVerifierLengthAndCharset() {
        let verifier = PKCE.makeVerifier()
        // 64 random bytes base64url-encode to 86 characters, inside the RFC 7636 43–128 window.
        XCTAssertEqual(verifier.count, 86)
        XCTAssertTrue((43...128).contains(verifier.count))
        XCTAssertNotNil(verifier.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
    }

    // MARK: challenge = BASE64URL(SHA256(verifier))

    func testChallengeMatchesRFC7636AppendixBVector() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testChallengeIsUnpaddedBase64URLOfSHA256() {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)

        // 32 digest bytes → 43 base64url characters once padding is stripped.
        XCTAssertEqual(challenge.count, 43)
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))

        let expected = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, expected)
    }

    // MARK: uniqueness

    func testVerifiersAndStatesAreUniqueAcrossInvocations() {
        let verifiers = (0..<100).map { _ in PKCE.makeVerifier() }
        let states = (0..<100).map { _ in PKCE.makeState() }
        XCTAssertEqual(Set(verifiers).count, verifiers.count)
        XCTAssertEqual(Set(states).count, states.count)
    }

    // MARK: state shape

    func testStateLengthAndCharset() {
        let state = PKCE.makeState()
        // 16 random bytes base64url-encode to 22 characters.
        XCTAssertEqual(state.count, 22)
        XCTAssertNotNil(state.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
    }
}
