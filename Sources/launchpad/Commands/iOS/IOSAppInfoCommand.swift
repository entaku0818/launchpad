import ArgumentParser
import Foundation

struct IOSAppInfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-info",
        abstract: "Manage localized app name, subtitle, and privacy policy URL",
        subcommands: [
            IOSAppInfoListCommand.self,
            IOSAppInfoUpdateCommand.self,
            IOSAppInfoSetLocaleCommand.self,
            IOSAppInfoCreateLocaleCommand.self,
            IOSAppInfoDeleteLocaleCommand.self,
        ]
    )
}

struct IOSAppInfoListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localized app info entries")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching app info for \(bid)")
        let appInfo = try await client.getAppInfo(appID: appID)
        guard let appInfoID = appInfo["id"] as? String else {
            Logger.error("No app info found"); Foundation.exit(1)
        }

        let locs = try await client.getAppInfoLocalizations(appInfoID: appInfoID)
        if locs.isEmpty { Logger.info("No localizations found"); return }
        Logger.info("\(locs.count) locale(s)\n")
        for l in locs {
            guard let id = l["id"] as? String,
                  let attrs = l["attributes"] as? [String: Any] else { continue }
            let locale   = attrs["locale"] as? String ?? "-"
            let name     = attrs["name"] as? String ?? "-"
            let subtitle = attrs["subtitle"] as? String ?? ""
            let ppURL    = attrs["privacyPolicyUrl"] as? String ?? ""
            print("  [\(locale)] \(name)\(subtitle.isEmpty ? "" : " — \(subtitle)")")
            print("    id: \(id)")
            if !ppURL.isEmpty { print("    privacyPolicyUrl: \(ppURL)") }
            print("")
        }
    }
}

struct IOSAppInfoUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update localized app name, subtitle, or privacy policy")

    @Option(name: .long, help: "App info localization ID (from app-info list)")
    var localizationID: String

    @Option(name: .long, help: "App name")
    var name: String?

    @Option(name: .long, help: "Subtitle (max 30 chars)")
    var subtitle: String?

    @Option(name: .long, help: "Privacy policy URL")
    var privacyPolicyURL: String?

    @Option(name: .long, help: "Privacy policy text")
    var privacyPolicyText: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating app info localization \(localizationID)")
        try await client.updateAppInfoLocalization(
            localizationID: localizationID,
            name: name,
            subtitle: subtitle,
            privacyPolicyURL: privacyPolicyURL,
            privacyPolicyText: privacyPolicyText
        )
        Logger.success("App info localization updated")
    }
}

struct IOSAppInfoCreateLocaleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create-locale", abstract: "Add a new locale to the app's localized info")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Locale code (e.g. ja, fr-FR)")
    var locale: String

    @Option(name: .long, help: "App name for this locale")
    var name: String?

    @Option(name: .long, help: "Subtitle")
    var subtitle: String?

    @Option(name: .long, help: "Privacy policy URL")
    var privacyPolicyURL: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        let info = try await client.getAppInfo(appID: appID)
        guard let appInfoID = info["id"] as? String else {
            Logger.error("App info not found"); Foundation.exit(1)
        }
        Logger.step("Creating '\(locale)' app info localization")
        let id = try await client.createAppInfoLocalization(appInfoID: appInfoID, locale: locale, name: name, subtitle: subtitle, privacyPolicyURL: privacyPolicyURL)
        Logger.success("Locale created: \(id)")
    }
}

struct IOSAppInfoDeleteLocaleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-locale", abstract: "Remove a locale from the app's localized info")

    @Option(name: .long, help: "App info localization ID (from app-info list)")
    var localizationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting app info localization \(localizationID)")
        try await client.deleteAppInfoLocalization(localizationID: localizationID)
        Logger.success("Locale deleted")
    }
}

struct IOSAppInfoSetLocaleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-locale", abstract: "Set the primary locale for the app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Primary locale code (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "Primary category ID (optional, from ios categories list)")
    var primaryCategoryID: String?

    @Option(name: .long, help: "Secondary category ID (optional)")
    var secondaryCategoryID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching app info for \(bid)")
        let info = try await client.getAppInfo(appID: appID)
        guard let infoID = info["id"] as? String else {
            Logger.error("App info not found"); Foundation.exit(1)
        }
        Logger.step("Updating primary locale to \(locale)")
        try await client.updateAppInfo(appInfoID: infoID, primaryLocale: locale, primaryCategoryID: primaryCategoryID, secondaryCategoryID: secondaryCategoryID)
        Logger.success("App info updated")
    }
}
