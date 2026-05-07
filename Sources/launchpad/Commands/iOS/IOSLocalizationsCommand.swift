import ArgumentParser
import Foundation

struct IOSLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "localizations",
        abstract: "Manage App Store version localizations (per-locale metadata)",
        subcommands: [
            IOSLocalizationsListCommand.self,
            IOSLocalizationsCreateCommand.self,
            IOSLocalizationsDeleteCommand.self,
        ]
    )
}

struct IOSLocalizationsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for an App Store version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching localizations for version \(versionID)")
        let locs = try await client.getLocalizations(versionID: versionID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale  = attrs["locale"] as? String ?? "-"
            let name    = attrs["name"] as? String ?? ""
            let state   = attrs["appStoreState"] as? String ?? ""
            print("  [\(locale)] \(name)  \(state)  id: \(id)")
        }
    }
}

struct IOSLocalizationsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new locale for an App Store version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    @Option(name: .long, help: "Locale code (e.g. ja, en-US, fr-FR)")
    var locale: String

    @Option(name: .long, help: "App name for this locale")
    var name: String?

    @Option(name: .long, help: "Description")
    var description: String?

    @Option(name: .long, help: "Keywords (comma-separated)")
    var keywords: String?

    @Option(name: .long, help: "What's new text")
    var whatsNew: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        var attrs: [String: Any] = [:]
        if let name        { attrs["name"] = name }
        if let description { attrs["description"] = description }
        if let keywords    { attrs["keywords"] = keywords }
        if let whatsNew    { attrs["whatsNewText"] = whatsNew }

        Logger.step("Creating '\(locale)' localization for version \(versionID)")
        let id = try await client.createLocalization(versionID: versionID, locale: locale, attributes: attrs)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSLocalizationsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a localization")

    @Option(name: .long, help: "Localization ID (from localizations list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting localization \(localizationID)")
        try await client.deleteLocalization(localizationID: localizationID)
        Logger.success("Localization deleted")
    }
}
