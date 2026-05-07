import ArgumentParser
import Foundation

struct AndroidListingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listings",
        abstract: "Read Play Store store listings",
        subcommands: [
            AndroidListingsListCommand.self,
            AndroidListingsGetCommand.self,
            AndroidListingsDeleteCommand.self,
        ]
    )
}

struct AndroidListingsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List all store listing locales")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching store listings for \(pkg)")
        let listings = try await client.listListings(packageName: pkg)

        if listings.isEmpty { Logger.info("No listings found"); return }
        Logger.info("\(listings.count) listing(s)\n")
        for listing in listings {
            let language = listing["language"] as? String ?? "-"
            let title    = listing["title"] as? String ?? ""
            print("  [\(language)] \(title)")
        }
    }
}

struct AndroidListingsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get store listing for a specific locale")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US, ja-JP)")
    var language: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching \(language) listing for \(pkg)")
        let listing = try await client.getListing(packageName: pkg, language: language)

        let title       = listing["title"] as? String ?? "-"
        let shortDesc   = listing["shortDescription"] as? String ?? ""
        let fullDesc    = listing["fullDescription"] as? String ?? ""
        let video       = listing["video"] as? String ?? ""

        print("Language:    \(language)")
        print("Title:       \(title)")
        if !shortDesc.isEmpty { print("Short desc:  \(shortDesc)") }
        if !fullDesc.isEmpty  { print("Full desc:\n\(fullDesc)") }
        if !video.isEmpty     { print("Promo video: \(video)") }
    }
}

struct AndroidListingsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete the store listing for a locale (commits the edit)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US, ja-JP)")
    var language: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deleting \(language) listing for \(pkg)")
        try await client.deleteListing(packageName: pkg, language: language)
        Logger.success("Listing deleted and edit committed")
    }
}
