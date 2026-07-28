import Foundation
import CryptoKit
import Security

enum PKCE {
    /// RFC 7636 requires a 43–128 character verifier; 64 random bytes yield about 86 base64url characters.
    static func makeVerifier() -> String {
        base64url(randomBytes(64))
    }

    /// RFC 7636 S256 challenge: base64url(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(digest))
    }

    static func makeState() -> String {
        base64url(randomBytes(16))
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        // Never continue with zero-filled verifier or state bytes.
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
