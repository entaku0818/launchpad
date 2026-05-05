import ArgumentParser
import Foundation

struct AndroidDeviceTiersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device-tiers",
        abstract: "List device tier configurations for targeted APK delivery"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching device tier configs for \(pkg)")
        let configs = try await client.listDeviceTierConfigs(packageName: pkg)

        if configs.isEmpty { Logger.info("No device tier configurations found"); return }

        Logger.info("\(configs.count) configuration(s)\n")
        for c in configs {
            let id = (c["deviceTierConfigId"] as? String) ?? (c["deviceTierConfigId"].map { "\($0)" } ?? "-")
            let tiers = c["deviceTiers"] as? [[String: Any]] ?? []
            print("  Config ID: \(id)")
            for t in tiers {
                let level = t["level"] as? Int ?? 0
                print("    tier \(level)")
            }
        }
    }
}
