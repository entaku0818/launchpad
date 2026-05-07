import ArgumentParser
import Foundation

struct IOSBetaAppLocalizationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "beta-app-info",
        abstract: "Manage per-locale TestFlight description, feedback email, and privacy URLs",
        subcommands: [
            IOSBetaAppInfoListCommand.self,
            IOSBetaAppInfoCreateCommand.self,
            IOSBetaAppInfoUpdateCommand.self,
        ]
    )
}

struct IOSBetaAppInfoListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List TestFlight app localizations")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching TestFlight app localizations for \(bid)")
        let locs = try await client.getBetaAppLocalizations(appID: appID)

        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) locale(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale = attrs["locale"] as? String ?? "-"
            let desc   = (attrs["description"] as? String ?? "").prefix(60)
            let email  = attrs["feedbackEmail"] as? String ?? "-"
            print("  [\(locale)] \(email)")
            print("    id: \(id)")
            if !desc.isEmpty { print("    desc: \(desc)…") }
            print("")
        }
    }
}

struct IOSBetaAppInfoCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a TestFlight localization entry")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Locale (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "TestFlight app description")
    var description: String

    @Option(name: .long, help: "Feedback email address")
    var feedbackEmail: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating '\(locale)' TestFlight localization")
        let id = try await client.createBetaAppLocalization(appID: appID, locale: locale, description: description, feedbackEmail: feedbackEmail)
        Logger.success("Localization created: \(id)")
    }
}

struct IOSBetaAppInfoUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a TestFlight localization entry")

    @Option(name: .long, help: "Localization ID (from beta-app-info list)")
    var localizationID: String

    @Option(name: .long, help: "App description for testers")
    var description: String?

    @Option(name: .long, help: "Feedback email address")
    var feedbackEmail: String?

    @Option(name: .long, help: "Marketing URL")
    var marketingURL: String?

    @Option(name: .long, help: "Privacy policy URL")
    var privacyPolicyURL: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating TestFlight localization \(localizationID)")
        try await client.updateBetaAppLocalization(
            localizationID: localizationID,
            description: description,
            feedbackEmail: feedbackEmail,
            marketingURL: marketingURL,
            privacyPolicyURL: privacyPolicyURL,
            tvOSPrivacyPolicy: nil
        )
        Logger.success("Localization updated")
    }
}
