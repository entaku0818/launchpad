import ArgumentParser
import Foundation

struct AndroidBundleListingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bundle-listings",
        abstract: "List per-bundle release notes for a specific bundle version code"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Bundle version code")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching bundle listings for version code \(versionCode)")
        let listings = try await client.listBundleListings(packageName: pkg, versionCode: versionCode)

        if listings.isEmpty { Logger.info("No bundle listings found"); return }
        Logger.info("\(listings.count) listing(s)\n")
        for listing in listings {
            let language      = listing["language"] as? String ?? "-"
            let recentChanges = listing["recentChanges"] as? String ?? ""
            print("  [\(language)]")
            if !recentChanges.isEmpty { print("    \(recentChanges.prefix(80))") }
        }
    }
}
