import ArgumentParser
import Foundation

struct AndroidRolloutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollout",
        abstract: "Set staged rollout percentage for a track"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (internal/alpha/beta/production)")
    var track: String = "production"

    @Option(name: .long, help: "Rollout percentage 0–100 (use 100 to complete rollout)")
    var percentage: Double

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        guard percentage >= 0, percentage <= 100 else {
            Logger.error("--percentage must be between 0 and 100")
            Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Setting \(track) rollout to \(percentage)% for \(pkg)")
        try await client.setRollout(packageName: pkg, track: track, percentage: percentage)

        if percentage >= 100 {
            Logger.success("Rollout completed — 100% of users will receive the update")
        } else {
            Logger.success("Rollout set to \(percentage)%")
        }
    }
}
