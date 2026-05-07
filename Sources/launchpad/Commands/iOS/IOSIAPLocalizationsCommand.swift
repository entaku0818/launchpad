import ArgumentParser
import Foundation

struct IOSIAPLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap-localizations",
        abstract: "Manage per-locale name and description for in-app purchases",
        subcommands: [
            IOSIAPLocListCommand.self,
            IOSIAPLocCreateCommand.self,
            IOSIAPLocUpdateCommand.self,
            IOSIAPLocDeleteCommand.self,
        ]
    )
}

struct IOSIAPLocListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for an IAP")

    @Option(name: .long, help: "IAP ID (from ios iap list)")
    var iapID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching IAP localizations for \(iapID)")
        let locs = try await client.listIAPLocalizations(iapID: iapID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale = attrs["locale"] as? String ?? "-"
            let name   = attrs["name"] as? String ?? "-"
            let desc   = (attrs["description"] as? String ?? "").prefix(60)
            print("  [\(locale)] \(name)  id: \(id)")
            if !desc.isEmpty { print("    \(desc)") }
        }
    }
}

struct IOSIAPLocCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an IAP localization")

    @Option(name: .long, help: "IAP ID")
    var iapID: String

    @Option(name: .long, help: "Locale code (e.g. ja, en-US)")
    var locale: String

    @Option(name: .long, help: "Display name")
    var name: String

    @Option(name: .long, help: "Optional description")
    var description: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating '\(locale)' localization for IAP \(iapID)")
        let id = try await client.createIAPLocalization(iapID: iapID, locale: locale, name: name, description: description)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSIAPLocUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update an IAP localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    @Option(name: .long, help: "Display name")
    var name: String?

    @Option(name: .long, help: "Description")
    var description: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating IAP localization \(localizationID)")
        try await client.updateIAPLocalization(localizationID: localizationID, name: name, description: description)
        Logger.success("Localization updated")
    }
}

struct IOSIAPLocDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an IAP localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting IAP localization \(localizationID)")
        try await client.deleteIAPLocalization(localizationID: localizationID)
        Logger.success("Localization deleted")
    }
}
