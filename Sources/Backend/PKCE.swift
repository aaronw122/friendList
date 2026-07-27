import Foundation
import CryptoKit
import Security

/// PKCE (RFC 7636) helpers for the Spotify Authorization Code + PKCE flow.
enum PKCE {
    /// 43–128 char high-entropy `code_verifier`. 64 random bytes → ~86 base64url chars.
    static func makeVerifier() -> String {
        base64url(randomBytes(64))
    }

    /// S256 challenge = base64url(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(digest))
    }

    /// Opaque CSRF `state` value.
    static func makeState() -> String {
        base64url(randomBytes(16))
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        // A zero-filled verifier/state would be a security hole — never proceed with one.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status))")
        return Data(bytes)
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
