import ArgumentParser
import Foundation

struct AndroidShareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "share",
        abstract: "Upload AAB to Internal App Sharing and return a download link"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Path to .aab file")
    var aab: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: aab) else {
            Logger.error("AAB file not found: \(aab)")
            Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Uploading \(aab) to Internal App Sharing")
        let url = try await client.shareInternally(packageName: pkg, aabPath: aab)

        Logger.success("Upload complete!")
        print("\n  Share URL: \(url)\n")
        Logger.info("Share this link with testers. Access is restricted to opted-in testers.")
    }
}
