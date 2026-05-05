import ArgumentParser
import Foundation

struct AndroidPromoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "promote",
        abstract: "Promote a track to another (e.g. internal → production)"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Source track")
    var from: String = "internal"

    @Option(name: .long, help: "Destination track")
    var to: String = "production"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Promoting \(pkg): \(from) → \(to)")
        try await client.promoteTrack(packageName: pkg, from: from, to: to)
        Logger.success("Promoted to \(to) successfully.")
    }
}
