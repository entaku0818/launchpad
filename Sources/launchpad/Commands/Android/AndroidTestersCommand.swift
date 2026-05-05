import ArgumentParser
import Foundation

struct AndroidTestersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testers",
        abstract: "Manage alpha/beta tester email lists",
        subcommands: [
            AndroidTestersListCommand.self,
            AndroidTestersAddCommand.self,
            AndroidTestersRemoveCommand.self,
        ]
    )
}

struct AndroidTestersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List testers on a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (alpha or beta)")
    var track: String = "alpha"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching \(track) testers for \(pkg)")
        let emails = try await client.getTesters(packageName: pkg, track: track)

        if emails.isEmpty { Logger.info("No testers on \(track) track"); return }
        Logger.info("\(emails.count) tester(s) on \(track):\n")
        emails.forEach { print("  \($0)") }
    }
}

struct AndroidTestersAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add testers to a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (alpha or beta)")
    var track: String = "alpha"

    @Option(name: .long, help: "Comma-separated email addresses to add")
    var emails: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        let newEmails = emails.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        Logger.step("Fetching current \(track) testers")
        var current = try await client.getTesters(packageName: pkg, track: track)
        let before = current.count
        for e in newEmails where !current.contains(e) { current.append(e) }

        Logger.step("Updating tester list (\(before) → \(current.count))")
        try await client.setTesters(packageName: pkg, track: track, emails: current)
        Logger.success("Added \(current.count - before) tester(s) to \(track)")
    }
}

struct AndroidTestersRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove testers from a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (alpha or beta)")
    var track: String = "alpha"

    @Option(name: .long, help: "Comma-separated email addresses to remove")
    var emails: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        let removeEmails = Set(emails.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })

        Logger.step("Fetching current \(track) testers")
        let current = try await client.getTesters(packageName: pkg, track: track)
        let updated = current.filter { !removeEmails.contains($0) }

        Logger.step("Updating tester list (\(current.count) → \(updated.count))")
        try await client.setTesters(packageName: pkg, track: track, emails: updated)
        Logger.success("Removed \(current.count - updated.count) tester(s) from \(track)")
    }
}
