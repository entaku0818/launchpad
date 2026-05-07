import ArgumentParser
import Foundation

struct IOSVersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "Manage App Store versions",
        subcommands: [
            IOSVersionsListCommand.self,
            IOSVersionsCreateCommand.self,
            IOSVersionsReleaseCommand.self,
        ]
    )
}

struct IOSVersionsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List App Store versions")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching versions for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let versions = try await client.listAppStoreVersions(appID: appID)

        if versions.isEmpty { Logger.info("No versions found"); return }
        for v in versions {
            guard let attrs = v["attributes"] as? [String: Any] else { continue }
            let ver      = attrs["versionString"] as? String ?? "-"
            let state    = attrs["appStoreState"] as? String ?? "-"
            let platform = attrs["platform"] as? String ?? "-"
            let created  = attrs["createdDate"] as? String ?? "-"
            print("  \(ver)  [\(state)]  \(platform)  created: \(created)")
        }
    }
}

struct IOSVersionsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new App Store version")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Version string (e.g. 2.1.0)")
    var version: String

    @Option(name: .long, help: "Platform (IOS, MAC_OS, TV_OS — default: IOS)")
    var platform: String = "IOS"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating App Store version \(version) for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let versionID = try await client.createAppStoreVersion(appID: appID, versionString: version, platform: platform)
        Logger.success("Version \(version) created  id: \(versionID)")
        Logger.info("Next: add metadata, screenshots, then submit for review")
    }
}

struct IOSVersionsReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "release", abstract: "Release a manually-held version that has passed App Store review")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Requesting release for version \(versionID)")
        let requestID = try await client.requestVersionRelease(versionID: versionID)
        Logger.success("Release request submitted: \(requestID)")
    }
}
