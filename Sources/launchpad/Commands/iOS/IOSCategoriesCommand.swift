import ArgumentParser
import Foundation

struct IOSCategoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "categories",
        abstract: "Show or set app primary and secondary categories",
        subcommands: [IOSCategoriesGetCommand.self, IOSCategoriesSetCommand.self],
        defaultSubcommand: IOSCategoriesGetCommand.self
    )
}

struct IOSCategoriesGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show app primary and secondary categories")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching app info for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let appInfo = try await client.getAppInfo(appID: appID)

        guard let attrs = appInfo["attributes"] as? [String: Any] else {
            Logger.info("No app info found"); return
        }

        let state = attrs["appStoreState"] as? String ?? "-"
        print("\nApp Store state: \(state)")

        if let rels = appInfo["relationships"] as? [String: Any] {
            if let primary = (rels["primaryCategory"] as? [String: Any])?["data"] as? [String: Any] {
                print("Primary category:   \(primary["id"] as? String ?? "-")")
            }
            if let secondary = (rels["secondaryCategory"] as? [String: Any])?["data"] as? [String: Any] {
                print("Secondary category: \(secondary["id"] as? String ?? "-")")
            }
        }
    }
}

struct IOSCategoriesSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set app primary (and optional secondary) category")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Primary category ID (e.g. MUSIC, LIFESTYLE, UTILITIES)")
    var primary: String

    @Option(name: .long, help: "Secondary category ID (optional)")
    var secondary: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Setting category for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let appInfo = try await client.getAppInfo(appID: appID)
        guard let appInfoID = appInfo["id"] as? String else {
            Logger.error("App info not found"); Foundation.exit(1)
        }

        try await client.updateAppInfo(appInfoID: appInfoID, primaryLocale: nil, primaryCategoryID: primary, secondaryCategoryID: secondary)
        Logger.success("Category set: primary=\(primary)\(secondary.map { ", secondary=\($0)" } ?? "")")
    }
}
