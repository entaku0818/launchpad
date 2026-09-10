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
        return ASCCredentials(
            keyID: keyID,
            issuerID: issuerID,
            keyContent: normalizePEM(keyContent)
        )
    }

    /// PEM を実改行に正規化する。
    ///
    /// `DotEnv` は自分がセットする値の `\n` を復元するが、既にセット済みの環境変数は
    /// 上書きしない設計なので、`export` や `set -a; . fastlane/.env` のようにシェル側から
    /// 渡された値はエスケープされたままここに届く。その状態だと
    /// `P256.Signing.PrivateKey(pemRepresentation:)` も altool 向けに書き出す .p8 も
    /// 両方壊れる（altool は `(-39) does not contain a valid authentication key`）。
    /// 入口で一度だけ正規化して、以降は常に実改行の PEM として扱う。
    static func normalizePEM(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 値ごと引用符で囲まれたまま渡ってくるケースを剥がす
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }

        // リテラルのエスケープを実改行へ。\r\n を先に処理しないと \r が残る
        value = value.replacingOccurrences(of: "\\r\\n", with: "\n")
        value = value.replacingOccurrences(of: "\\n", with: "\n")
        value = value.replacingOccurrences(of: "\r\n", with: "\n")

        return value
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
        let pem = keyContent.hasSuffix("\n") ? keyContent : keyContent + "\n"
        try pem.write(to: path, atomically: true, encoding: .utf8)
        // 秘密鍵をホーム配下に 644 で残さない
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
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
