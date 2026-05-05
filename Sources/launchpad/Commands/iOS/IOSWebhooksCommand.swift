import ArgumentParser
import Foundation

struct IOSWebhooksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webhooks",
        abstract: "Manage App Store Connect webhook notifications",
        subcommands: [
            IOSWebhooksListCommand.self,
            IOSWebhooksCreateCommand.self,
            IOSWebhooksDeleteCommand.self,
        ]
    )
}

// MARK: - list

struct IOSWebhooksListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured webhooks"
    )

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching webhooks")
        let webhooks = try await client.listWebhooks()

        if webhooks.isEmpty { Logger.info("No webhooks configured"); return }

        Logger.info("\(webhooks.count) webhook(s)\n")
        for w in webhooks {
            guard let id = w["id"] as? String,
                  let attrs = w["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let url     = attrs["endpoint"] as? String ?? "-"
            let enabled = attrs["isEnabled"] as? Bool ?? false
            print("  \(name)  [\(enabled ? "enabled" : "disabled")]")
            print("    url: \(url)")
            print("    id:  \(id)\n")
        }
    }
}

// MARK: - create

struct IOSWebhooksCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new webhook"
    )

    @Option(name: .long, help: "Webhook name")
    var name: String

    @Option(name: .long, help: "Endpoint URL (must be HTTPS)")
    var url: String

    @Option(name: .long, help: "Shared secret for HMAC signature verification")
    var secret: String

    mutating func run() async throws {
        DotEnv.load()

        guard url.hasPrefix("https://") else {
            Logger.error("Endpoint URL must use HTTPS"); Foundation.exit(1)
        }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Creating webhook '\(name)'")
        let id = try await client.createWebhook(name: name, url: url, secret: secret)
        Logger.success("Webhook created  id: \(id)")
        Logger.info("Events: build uploads, version state changes, review decisions, TestFlight feedback")
    }
}

// MARK: - delete

struct IOSWebhooksDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a webhook"
    )

    @Option(name: .long, help: "Webhook ID")
    var webhookID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Deleting webhook \(webhookID)")
        try await client.deleteWebhook(id: webhookID)
        Logger.success("Webhook deleted")
    }
}
