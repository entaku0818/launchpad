import ArgumentParser
import Foundation

struct AndroidBuildsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builds",
        abstract: "List uploaded AAB bundles"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching uploaded bundles for \(pkg)")
        let bundles = try await client.listBundles(packageName: pkg)

        if bundles.isEmpty { Logger.info("No bundles found in current edit"); return }

        Logger.info("\(bundles.count) bundle(s)\n")
        for b in bundles {
            let versionCode = b["versionCode"] as? Int ?? 0
            let sha1        = b["sha1"] as? String ?? "-"
            let sha256      = b["sha256"] as? String ?? "-"
            print("  versionCode: \(versionCode)")
            print("    sha1:   \(sha1)")
            print("    sha256: \(sha256)\n")
        }
    }
}
