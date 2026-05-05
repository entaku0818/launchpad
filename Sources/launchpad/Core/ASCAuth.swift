import CryptoKit
import Foundation

struct ASCCredentials {
    let keyID: String
    let issuerID: String
    let keyContent: String

    static func fromEnvironment() throws -> ASCCredentials {
        guard
            let keyID = ProcessInfo.processInfo.environment["APP_STORE_CONNECT_API_KEY_KEY_ID"],
            let issuerID = ProcessInfo.processInfo.environment["APP_STORE_CONNECT_API_KEY_ISSUER_ID"],
            let keyContent = ProcessInfo.processInfo.environment["APP_STORE_CONNECT_API_KEY_CONTENT"]
        else {
            throw LaunchpadError.missingEnvironmentVariable(
                "APP_STORE_CONNECT_API_KEY_KEY_ID / ISSUER_ID / CONTENT"
            )
        }
        return ASCCredentials(keyID: keyID, issuerID: issuerID, keyContent: keyContent)
    }

    func generateJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let header = try jsonBase64url(["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let payload = try jsonBase64url([
            "iss": issuerID,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
        ] as [String: Any])

        let signingInput = "\(header).\(payload)"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: keyContent)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return "\(signingInput).\(base64url(signature.rawRepresentation))"
    }

    // Write p8 key to ~/private_keys/ for altool compatibility
    func writeKeyFile() throws -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("private_keys")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("AuthKey_\(keyID).p8")
        try keyContent.write(to: path, atomically: true, encoding: .utf8)
        return path.path
    }
}

private func jsonBase64url(_ dict: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: dict)
    return base64url(data)
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
