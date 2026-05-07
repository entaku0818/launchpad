import ArgumentParser
import Foundation

struct IOSEventLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "event-localizations",
        abstract: "Manage per-locale content for in-app events",
        subcommands: [
            IOSEventLocListCommand.self,
            IOSEventLocCreateCommand.self,
            IOSEventLocUpdateCommand.self,
            IOSEventLocDeleteCommand.self,
        ]
    )
}

struct IOSEventLocListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for an event")

    @Option(name: .long, help: "Event ID (from ios events list)")
    var eventID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching localizations for event \(eventID)")
        let locs = try await client.listAppEventLocalizations(eventID: eventID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale    = attrs["locale"] as? String ?? "-"
            let name      = attrs["name"] as? String ?? "-"
            let shortDesc = (attrs["shortDescription"] as? String ?? "").prefix(60)
            print("  [\(locale)] \(name)  id: \(id)")
            if !shortDesc.isEmpty { print("    \(shortDesc)") }
        }
    }
}

struct IOSEventLocCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a localization for an event")

    @Option(name: .long, help: "Event ID")
    var eventID: String

    @Option(name: .long, help: "Locale code (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "Display name shown in App Store")
    var name: String

    @Option(name: .long, help: "Short description (optional)")
    var shortDescription: String?

    @Option(name: .long, help: "Long description (optional)")
    var longDescription: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating '\(locale)' localization for event \(eventID)")
        let id = try await client.createAppEventLocalization(
            eventID: eventID, locale: locale, name: name,
            shortDescription: shortDescription, longDescription: longDescription
        )
        Logger.success("Localization created: \(id)")
    }
}

struct IOSEventLocUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update an event localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    @Option(name: .long, help: "Display name")
    var name: String?

    @Option(name: .long, help: "Short description")
    var shortDescription: String?

    @Option(name: .long, help: "Long description")
    var longDescription: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating event localization \(localizationID)")
        try await client.updateAppEventLocalization(localizationID: localizationID, name: name, shortDescription: shortDescription, longDescription: longDescription)
        Logger.success("Localization updated")
    }
}

struct IOSEventLocDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an event localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting event localization \(localizationID)")
        try await client.deleteAppEventLocalization(localizationID: localizationID)
        Logger.success("Localization deleted")
    }
}
