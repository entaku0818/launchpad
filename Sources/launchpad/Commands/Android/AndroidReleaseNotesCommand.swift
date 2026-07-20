import ArgumentParser
import Foundation

struct AndroidReleaseNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-notes",
        abstract: "Manage per-release notes for a specific version code on a track",
        subcommands: [
            AndroidReleaseNotesListCommand.self,
            AndroidReleaseNotesUpdateCommand.self,
        ]
    )
}

struct AndroidReleaseNotesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List release notes for a version code on a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (e.g. production, internal, beta)")
    var track: String

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching release notes for version code \(versionCode) on track '\(track)'")
        let notes = try await client.listReleaseNotes(packageName: pkg, track: track, versionCode: versionCode)

        if notes.isEmpty { Logger.info("No release notes found"); return }
        Logger.info("\(notes.count) release note(s)\n")
        for note in notes {
            let language = note["language"] as? String ?? "-"
            let text     = note["text"] as? String ?? ""
            print("  [\(language)]")
            if !text.isEmpty { print("    \(text.prefix(80))") }
        }
    }
}

struct AndroidReleaseNotesUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Set release notes for a version code and locale on a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track name (e.g. production, internal, beta)")
    var track: String

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    @Option(name: .long, help: "Language code (e.g. en-US)")
    var language: String

    @Option(name: .long, help: "Release notes text")
    var recentChanges: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Updating \(language) release notes for version code \(versionCode) on track '\(track)'")
        try await client.updateReleaseNotes(packageName: pkg, track: track, versionCode: versionCode, language: language, recentChanges: recentChanges)
        Logger.success("Release notes updated and edit committed")
    }
}
