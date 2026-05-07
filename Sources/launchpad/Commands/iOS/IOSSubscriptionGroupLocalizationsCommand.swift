import ArgumentParser
import Foundation

struct IOSSubscriptionGroupLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-group-localizations",
        abstract: "Manage localized names for a subscription group",
        subcommands: [
            IOSSGLocListCommand.self,
            IOSSGLocCreateCommand.self,
            IOSSGLocUpdateCommand.self,
            IOSSGLocDeleteCommand.self,
        ]
    )
}

struct IOSSGLocListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for a subscription group")

    @Option(name: .long, help: "Subscription group ID (from ios subscription-groups list)")
    var groupID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching localizations for subscription group \(groupID)")
        let locs = try await client.listSubscriptionGroupLocalizations(groupID: groupID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale        = attrs["locale"] as? String ?? "-"
            let name          = attrs["name"] as? String ?? "-"
            let customAppName = attrs["customAppName"] as? String ?? ""
            print("  [\(locale)] \(name)  id: \(id)")
            if !customAppName.isEmpty { print("    customAppName: \(customAppName)") }
        }
    }
}

struct IOSSGLocCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a localization for a subscription group")

    @Option(name: .long, help: "Subscription group ID")
    var groupID: String

    @Option(name: .long, help: "Locale code (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "Displayed name for the subscription group")
    var name: String

    @Option(name: .long, help: "Custom app name to show in the subscription row (optional)")
    var customAppName: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating '\(locale)' localization for subscription group \(groupID)")
        let id = try await client.createSubscriptionGroupLocalization(groupID: groupID, locale: locale, name: name, customAppName: customAppName)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSSGLocUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a subscription group localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    @Option(name: .long, help: "Displayed name for the subscription group")
    var name: String?

    @Option(name: .long, help: "Custom app name")
    var customAppName: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating subscription group localization \(localizationID)")
        try await client.updateSubscriptionGroupLocalization(localizationID: localizationID, name: name, customAppName: customAppName)
        Logger.success("Localization updated")
    }
}

struct IOSSGLocDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription group localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting subscription group localization \(localizationID)")
        try await client.deleteSubscriptionGroupLocalization(localizationID: localizationID)
        Logger.success("Localization deleted")
    }
}
