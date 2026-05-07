import ArgumentParser
import Foundation

struct AndroidApksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apks",
        abstract: "List uploaded APK files"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching uploaded APKs for \(pkg)")
        let apks = try await client.listApks(packageName: pkg)

        if apks.isEmpty { Logger.info("No APKs found in current edit"); return }

        Logger.info("\(apks.count) APK(s)\n")
        for a in apks {
            let versionCode = a["versionCode"] as? Int ?? 0
            let binary      = a["binary"] as? [String: Any]
            let sha1        = binary?["sha1"] as? String ?? a["sha1"] as? String ?? "-"
            let sha256      = binary?["sha256"] as? String ?? a["sha256"] as? String ?? "-"
            print("  versionCode: \(versionCode)")
            print("    sha1:   \(sha1)")
            print("    sha256: \(sha256)\n")
        }
    }
}
