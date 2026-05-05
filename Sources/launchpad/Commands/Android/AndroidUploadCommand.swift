import ArgumentParser
import Foundation

struct AndroidUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload AAB to Google Play"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track (internal, alpha, beta, production)")
    var track: String = "internal"

    @Option(name: .long, help: "Path to .aab file")
    var aab: String?

    @Flag(name: .long, help: "Upload metadata only (no binary)")
    var metadataOnly: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName in .launchpadrc required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        if metadataOnly {
            Logger.step("Uploading metadata to Google Play (\(track))")
            try await client.uploadMetadata(packageName: pkg, track: track)
        } else {
            guard let aabPath = aab else {
                Logger.error("--aab is required")
                Foundation.exit(1)
            }
            Logger.step("Uploading \(aabPath) to Google Play (\(track))")
            try await client.uploadAAB(packageName: pkg, aabPath: aabPath, track: track)
        }

        Logger.success("Upload complete.")
    }
}
