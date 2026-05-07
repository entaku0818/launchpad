import ArgumentParser
import Foundation

struct IOSScreenshotSetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot-sets",
        abstract: "Manage screenshot set slots for an App Store version localization",
        subcommands: [
            IOSScreenshotSetsListCommand.self,
            IOSScreenshotSetsCreateCommand.self,
            IOSScreenshotSetsDeleteCommand.self,
        ]
    )
}

struct IOSScreenshotSetsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List screenshot sets for a localization")

    @Option(name: .long, help: "Localization ID (from ios localizations list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching screenshot sets for localization \(localizationID)")
        let sets = try await client.getScreenshotSets(localizationID: localizationID)

        if sets.isEmpty { Logger.info("No screenshot sets found"); return }
        Logger.info("\(sets.count) set(s)\n")
        for s in sets {
            guard let id = s["id"] as? String,
                  let attrs = s["attributes"] as? [String: Any] else { continue }
            let displayType = attrs["screenshotDisplayType"] as? String ?? "-"
            print("  \(displayType)  id: \(id)")
        }
    }
}

struct IOSScreenshotSetsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a screenshot set slot for a specific display type")

    @Option(name: .long, help: "Localization ID (from ios localizations list)")
    var localizationID: String

    @Option(name: .long, help: "Display type, e.g. APP_IPHONE_67, APP_IPHONE_61, APP_IPAD_PRO_3GEN_129")
    var displayType: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating \(displayType) screenshot set")
        let id = try await client.createScreenshotSet(localizationID: localizationID, screenshotDisplayType: displayType)
        Logger.success("Screenshot set created: \(id)")
    }
}

struct IOSScreenshotSetsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a screenshot set and all its screenshots")

    @Option(name: .long, help: "Screenshot set ID (from list)")
    var setID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting screenshot set \(setID)")
        try await client.deleteScreenshotSet(setID: setID)
        Logger.success("Screenshot set deleted")
    }
}
