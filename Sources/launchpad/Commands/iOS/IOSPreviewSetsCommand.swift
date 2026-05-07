import ArgumentParser
import Foundation

struct IOSPreviewSetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview-sets",
        abstract: "Manage preview set slots for an App Store version localization",
        subcommands: [
            IOSPreviewSetsListCommand.self,
            IOSPreviewSetsCreateCommand.self,
            IOSPreviewSetsDeleteCommand.self,
        ]
    )
}

struct IOSPreviewSetsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List preview sets for a localization")

    @Option(name: .long, help: "Localization ID (from ios localizations list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching preview sets for localization \(localizationID)")
        let sets = try await client.getPreviewSets(localizationID: localizationID)

        if sets.isEmpty { Logger.info("No preview sets found"); return }
        Logger.info("\(sets.count) set(s)\n")
        for s in sets {
            guard let id = s["id"] as? String,
                  let attrs = s["attributes"] as? [String: Any] else { continue }
            let previewType = attrs["previewType"] as? String ?? "-"
            print("  \(previewType)  id: \(id)")
        }
    }
}

struct IOSPreviewSetsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a preview set slot for a specific display type")

    @Option(name: .long, help: "Localization ID (from ios localizations list)")
    var localizationID: String

    @Option(name: .long, help: "Preview type, e.g. IPHONE_67, IPHONE_61, IPAD_PRO_3GEN_129")
    var previewType: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating \(previewType) preview set")
        let id = try await client.createPreviewSet(localizationID: localizationID, previewType: previewType)
        Logger.success("Preview set created: \(id)")
    }
}

struct IOSPreviewSetsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a preview set and all its previews")

    @Option(name: .long, help: "Preview set ID (from list)")
    var setID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting preview set \(setID)")
        try await client.deletePreviewSet(setID: setID)
        Logger.success("Preview set deleted")
    }
}
