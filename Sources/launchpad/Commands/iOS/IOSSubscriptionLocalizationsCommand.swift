import ArgumentParser
import Foundation

struct IOSSubscriptionLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-localizations",
        abstract: "Manage per-locale name and description for subscriptions",
        subcommands: [
            IOSSubLocListCommand.self,
            IOSSubLocCreateCommand.self,
            IOSSubLocUpdateCommand.self,
            IOSSubLocDeleteCommand.self,
        ]
    )
}

struct IOSSubLocListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching subscription localizations")
        let locs = try await client.listSubscriptionLocalizations(subscriptionID: subscriptionID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale = attrs["locale"] as? String ?? "-"
            let name   = attrs["name"] as? String ?? "-"
            let desc   = (attrs["description"] as? String ?? "").prefix(50)
            print("  [\(locale)] \(name)  id: \(id)")
            if !desc.isEmpty { print("    \(desc)") }
        }
    }
}

struct IOSSubLocCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a subscription localization")

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Locale code (e.g. ja, en-US)")
    var locale: String

    @Option(name: .long, help: "Subscription display name")
    var name: String

    @Option(name: .long, help: "Optional description")
    var description: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating '\(locale)' localization")
        let id = try await client.createSubscriptionLocalization(subscriptionID: subscriptionID, locale: locale, name: name, description: description)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSSubLocUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a subscription localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    @Option(name: .long, help: "Subscription display name")
    var name: String?

    @Option(name: .long, help: "Description")
    var description: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating localization \(localizationID)")
        try await client.updateSubscriptionLocalization(localizationID: localizationID, name: name, description: description)
        Logger.success("Localization updated")
    }
}

struct IOSSubLocDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting localization \(localizationID)")
        try await client.deleteSubscriptionLocalization(localizationID: localizationID)
        Logger.success("Localization deleted")
    }
}
