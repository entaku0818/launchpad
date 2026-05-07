import ArgumentParser
import Foundation

struct IOSCustomPageLocalizationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "custom-page-localizations",
        abstract: "Manage localizations for custom product page versions",
        subcommands: [
            IOSCustomPageLocListCommand.self,
            IOSCustomPageLocCreateCommand.self,
            IOSCustomPageLocUpdateCommand.self,
        ]
    )
}

struct IOSCustomPageLocListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations for a custom product page version")

    @Option(name: .long, help: "Custom product page version ID (from ios product-pages list)")
    var pageVersionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching localizations for page version \(pageVersionID)")
        let locs = try await client.listCustomProductPageLocalizations(pageVersionID: pageVersionID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) localization(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale = attrs["locale"] as? String ?? "-"
            let text   = (attrs["promotionalText"] as? String ?? "").prefix(50)
            print("  [\(locale)]  id: \(id)")
            if !text.isEmpty { print("    \(text)") }
        }
    }
}

struct IOSCustomPageLocCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a localization for a custom product page version")

    @Option(name: .long, help: "Custom product page version ID")
    var pageVersionID: String

    @Option(name: .long, help: "Locale code (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "Promotional text (optional)")
    var promotionalText: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating '\(locale)' localization for page version \(pageVersionID)")
        let id = try await client.createCustomProductPageLocalization(pageVersionID: pageVersionID, locale: locale, promotionalText: promotionalText)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSCustomPageLocUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update promotional text for a custom page localization")

    @Option(name: .long, help: "Localization ID (from list)")
    var localizationID: String

    @Option(name: .long, help: "Promotional text")
    var promotionalText: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating localization \(localizationID)")
        try await client.updateCustomProductPageLocalization(localizationID: localizationID, promotionalText: promotionalText)
        Logger.success("Localization updated")
    }
}
