import ArgumentParser
import Foundation

struct IOSVersionBumpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version-bump",
        abstract: "Bump the local xcodeproj version number",
        subcommands: [
            IOSVersionBumpMarketingCommand.self,
            IOSVersionBumpBuildCommand.self,
            IOSVersionBumpShowCommand.self,
        ]
    )
}

// MARK: - show

struct IOSVersionBumpShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show current version and build number")

    @Option(name: .long, help: "Xcode project path (.xcodeproj) [config: ios.project]")
    var project: String?

    @Option(name: .long, help: "Build scheme [config: ios.scheme]")
    var scheme: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let proj = project ?? cfg?.project ?? { Logger.error("--project or ios.project in .launchpadrc required"); Foundation.exit(1) }()
        let sch  = scheme  ?? cfg?.scheme  ?? { Logger.error("--scheme or ios.scheme in .launchpadrc required"); Foundation.exit(1) }()

        let version = try XcodeProject.versionNumber(project: proj, target: sch)
        let build   = try XcodeProject.buildNumber(project: proj, target: sch)
        print("  Version: \(version)")
        print("  Build:   \(build)")
    }
}

// MARK: - marketing version

struct IOSVersionBumpMarketingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Bump or set MARKETING_VERSION (e.g. 1.2.3)")

    @Option(name: .long, help: "Xcode project path (.xcodeproj) [config: ios.project]")
    var project: String?

    @Option(name: .long, help: "Build scheme [config: ios.scheme]")
    var scheme: String?

    @Flag(name: .long, help: "Increment patch component (1.0.0 → 1.0.1)")
    var patch: Bool = false

    @Flag(name: .long, help: "Increment minor component (1.0.0 → 1.1.0)")
    var minor: Bool = false

    @Flag(name: .long, help: "Increment major component (1.0.0 → 2.0.0)")
    var major: Bool = false

    @Option(name: .long, help: "Set exact version string (e.g. 2.0.0)")
    var set: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg  = Config.load().ios
        let proj = project ?? cfg?.project ?? { Logger.error("--project or ios.project in .launchpadrc required"); Foundation.exit(1) }()
        let sch  = scheme  ?? cfg?.scheme  ?? { Logger.error("--scheme or ios.scheme in .launchpadrc required"); Foundation.exit(1) }()

        let current = try XcodeProject.versionNumber(project: proj, target: sch)
        let next: String

        if let s = set {
            next = s
        } else if patch || minor || major {
            next = try bumpVersion(current, patch: patch, minor: minor, major: major)
        } else {
            Logger.error("Specify --patch, --minor, --major, or --set <version>")
            Foundation.exit(1)
        }

        let dir = URL(fileURLWithPath: proj).deletingLastPathComponent().path
        _ = try Shell.run(["xcrun", "agvtool", "new-marketing-version", next], cwd: dir)
        Logger.success("MARKETING_VERSION: \(current) → \(next)")
    }
}

// MARK: - build number

struct IOSVersionBumpBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "build", abstract: "Increment or set CURRENT_PROJECT_VERSION (build number)")

    @Option(name: .long, help: "Xcode project path (.xcodeproj) [config: ios.project]")
    var project: String?

    @Option(name: .long, help: "Build scheme [config: ios.scheme]")
    var scheme: String?

    @Option(name: .long, help: "Set exact build number instead of auto-incrementing")
    var set: Int?

    mutating func run() throws {
        DotEnv.load()
        let cfg  = Config.load().ios
        let proj = project ?? cfg?.project ?? { Logger.error("--project or ios.project in .launchpadrc required"); Foundation.exit(1) }()
        let sch  = scheme  ?? cfg?.scheme  ?? { Logger.error("--scheme or ios.scheme in .launchpadrc required"); Foundation.exit(1) }()

        let current = try XcodeProject.buildNumber(project: proj, target: sch)
        let dir = URL(fileURLWithPath: proj).deletingLastPathComponent().path

        if let n = set {
            _ = try Shell.run(["xcrun", "agvtool", "new-version", "-all", "\(n)"], cwd: dir)
            Logger.success("CURRENT_PROJECT_VERSION: \(current) → \(n)")
        } else {
            let next = try XcodeProject.incrementBuildNumber(project: proj)
            Logger.success("CURRENT_PROJECT_VERSION: \(current) → \(next)")
        }
    }
}

// MARK: - helper

private func bumpVersion(_ version: String, patch: Bool, minor: Bool, major: Bool) throws -> String {
    var parts = version.split(separator: ".").compactMap { Int($0) }
    while parts.count < 3 { parts.append(0) }
    if major {
        parts[0] += 1; parts[1] = 0; parts[2] = 0
    } else if minor {
        parts[1] += 1; parts[2] = 0
    } else {
        parts[2] += 1
    }
    return parts.map(String.init).joined(separator: ".")
}
