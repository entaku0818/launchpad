import ArgumentParser
import Foundation

struct IOSAPIKeysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "api-keys",
        abstract: "Manage App Store Connect API keys",
        subcommands: [
            IOSAPIKeysListCommand.self,
            IOSAPIKeysCreateCommand.self,
            IOSAPIKeysRevokeCommand.self,
        ]
    )
}

struct IOSAPIKeysListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List API keys")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching API keys")
        let keys = try await client.listAPIKeys()

        if keys.isEmpty { Logger.info("No API keys found"); return }
        Logger.info("\(keys.count) key(s)\n")
        for k in keys {
            guard let id = k["id"] as? String,
                  let attrs = k["attributes"] as? [String: Any] else { continue }
            let name    = attrs["nickname"] as? String ?? "-"
            let roles   = (attrs["roles"] as? [String] ?? []).joined(separator: ", ")
            let expires = attrs["expirationDate"] as? String ?? "-"
            let canDl   = attrs["isActive"] as? Bool ?? false
            print("  \(name)")
            print("    id:      \(id)")
            print("    roles:   \(roles)")
            print("    active:  \(canDl)  expires: \(expires)\n")
        }
    }
}

struct IOSAPIKeysCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an API key")

    @Option(name: .long, help: "Key name")
    var name: String

    @Option(name: .long, help: "Comma-separated roles: ADMIN, FINANCE, TECHNICAL, SALES, MARKETING, ACCOUNT_HOLDER, DEVELOPER, APP_MANAGER, CUSTOMER_SUPPORT, ACCESS_TO_REPORTS, CREATE_APPS")
    var roles: String = "DEVELOPER"

    mutating func run() async throws {
        DotEnv.load()
        let roleList = roles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating API key '\(name)' with roles: \(roleList.joined(separator: ", "))")
        let key = try await client.createAPIKey(name: name, roles: roleList)

        if let attrs = key["attributes"] as? [String: Any] {
            let id         = key["id"] as? String ?? "-"
            let privateKey = attrs["privateKey"] as? String ?? ""
            print("\nKey ID: \(id)")
            if !privateKey.isEmpty {
                print("Private key (save this — shown only once):\n\(privateKey)")
            }
        }
        Logger.success("API key created")
    }
}

struct IOSAPIKeysRevokeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "revoke", abstract: "Revoke an API key")

    @Option(name: .long, help: "Key ID")
    var keyID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Revoking API key \(keyID)")
        try await client.revokeAPIKey(keyID: keyID)
        Logger.success("API key revoked")
    }
}
