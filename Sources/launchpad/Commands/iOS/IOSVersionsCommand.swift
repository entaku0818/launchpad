import ArgumentParser
import Foundation

struct IOSVersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "Manage App Store versions",
        subcommands: [
            IOSVersionsListCommand.self,
            IOSVersionsGetCommand.self,
            IOSVersionsCreateCommand.self,
            IOSVersionsUpdateCommand.self,
            IOSVersionsDeleteCommand.self,
            IOSVersionsReleaseCommand.self,
        ]
    )
}

struct IOSVersionsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show details of a specific App Store version by ID")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching version \(versionID)")
        let version = try await client.getAppStoreVersionDetail(versionID: versionID)

        guard let attrs = version["attributes"] as? [String: Any] else {
            Logger.info("Version not found"); return
        }
        let ver          = attrs["versionString"] as? String ?? "-"
        let state        = attrs["appStoreState"] as? String ?? "-"
        let releaseType  = attrs["releaseType"] as? String ?? "-"
        let platform     = attrs["platform"] as? String ?? "-"
        let created      = attrs["createdDate"] as? String ?? "-"
        let scheduleDate = attrs["earliestReleaseDate"] as? String ?? ""
        let useEncrypt   = attrs["usesNonExemptEncryption"] as? Bool ?? false

        print("Version:          \(ver)")
        print("State:            \(state)")
        print("Platform:         \(platform)")
        print("Release type:     \(releaseType)")
        print("Encryption:       \(useEncrypt)")
        print("Created:          \(created)")
        if !scheduleDate.isEmpty { print("Scheduled date:   \(scheduleDate)") }

        if let included = version["relationships"] as? [String: Any],
           let locs = (included["appStoreVersionLocalizations"] as? [String: Any])?["data"] as? [[String: Any]] {
            print("Localizations:    \(locs.count) locale(s)")
        }
    }
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

struct IOSVersionsUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update version settings (release type, encryption, scheduled release date)")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.1)")
    var versionString: String?

    @Option(name: .long, help: "Release type: MANUAL, AFTER_APPROVAL, or SCHEDULED")
    var releaseType: String?

    @Option(name: .long, help: "Earliest release date (ISO 8601, used with SCHEDULED release type)")
    var earliestReleaseDate: String?

    @Flag(name: .long, help: "Mark as using non-exempt encryption")
    var usesNonExemptEncryption: Bool = false

    @Flag(name: .long, help: "Mark as NOT using non-exempt encryption")
    var noEncryption: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let encryptionFlag: Bool? = usesNonExemptEncryption ? true : (noEncryption ? false : nil)
        Logger.step("Updating version \(versionID)")
        try await client.updateAppStoreVersion(
            versionID: versionID,
            versionString: versionString,
            releaseType: releaseType,
            earliestReleaseDate: earliestReleaseDate,
            usesNonExemptEncryption: encryptionFlag
        )
        Logger.success("Version updated")
    }
}

struct IOSVersionsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a version in PREPARE_FOR_SUBMISSION state")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting version \(versionID)")
        try await client.deleteAppStoreVersion(versionID: versionID)
        Logger.success("Version deleted")
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
