import ArgumentParser
import Foundation

struct AndroidApkListingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apk-listings",
        abstract: "Manage per-APK version release notes",
        subcommands: [
            AndroidApkListingsListCommand.self,
            AndroidApkListingsUpdateCommand.self,
        ]
    )
}

struct AndroidApkListingsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List release notes for a specific APK version code")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "APK version code")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching APK listings for version code \(versionCode)")
        let listings = try await client.listApkListings(packageName: pkg, versionCode: versionCode)

        if listings.isEmpty { Logger.info("No APK listings found"); return }
        Logger.info("\(listings.count) listing(s)\n")
        for listing in listings {
            let language      = listing["language"] as? String ?? "-"
            let recentChanges = listing["recentChanges"] as? String ?? ""
            print("  [\(language)]")
            if !recentChanges.isEmpty { print("    \(recentChanges.prefix(80))") }
        }
    }
}

struct AndroidApkListingsUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Set release notes for a specific APK version and locale")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "APK version code")
    var versionCode: Int

    @Option(name: .long, help: "Language code (e.g. en-US)")
    var language: String

    @Option(name: .long, help: "Release notes text")
    var recentChanges: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Updating \(language) APK listing for version code \(versionCode)")
        try await client.updateApkListing(packageName: pkg, versionCode: versionCode, language: language, recentChanges: recentChanges)
        Logger.success("APK listing updated and edit committed")
    }
}
