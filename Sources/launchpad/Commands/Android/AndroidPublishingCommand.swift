import ArgumentParser
import Foundation

struct AndroidPublishingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publishing",
        abstract: "Manage Play Store managed publishing (manual release control)",
        subcommands: [
            AndroidPublishingStatusCommand.self,
            AndroidPublishingEnableCommand.self,
            AndroidPublishingDisableCommand.self,
        ]
    )
}

struct AndroidPublishingStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show managed publishing status")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching publishing settings for \(pkg)")
        let info = try await client.getManagedPublishing(packageName: pkg)

        let autoPublish = info["isAutoPublishEnabled"] as? Bool ?? true
        let mode = autoPublish ? "Auto-publish (changes go live immediately after review)" : "Managed (manual publish required)"
        print("\nPublishing mode: \(mode)")
    }
}

struct AndroidPublishingEnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Enable managed publishing (require manual publish)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Enabling managed publishing for \(pkg)")
        try await client.setManagedPublishing(packageName: pkg, enabled: true)
        Logger.success("Managed publishing enabled — changes will not go live until manually published")
    }
}

struct AndroidPublishingDisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disable", abstract: "Disable managed publishing (auto-publish after review)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Disabling managed publishing for \(pkg)")
        try await client.setManagedPublishing(packageName: pkg, enabled: false)
        Logger.success("Auto-publish enabled — changes go live immediately after review")
    }
}
