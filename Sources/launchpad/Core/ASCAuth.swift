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
}

// TODO: JWT生成実装 (#1)
