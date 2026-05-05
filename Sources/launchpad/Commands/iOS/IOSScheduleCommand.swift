import ArgumentParser
import Foundation

struct IOSScheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Schedule or configure the release date for an App Store version"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version (auto-read from xcodeproj if omitted)")
    var version: String?

    @Option(name: .long, help: "Release date in ISO8601 format (e.g. 2026-05-10T09:00:00Z). Omit for release after approval.")
    var date: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        if let date {
            guard ISO8601DateFormatter().date(from: date) != nil else {
                Logger.error("Invalid date format. Use ISO8601 (e.g. 2026-05-10T09:00:00Z)")
                Foundation.exit(1)
            }
        }

        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        let ver: String
        if let version {
            ver = version
        } else if let proj = cfg?.project, let tgt = cfg?.scheme {
            ver = try XcodeProject.versionNumber(project: proj, target: tgt)
        } else {
            Logger.error("--version or ios.project + ios.scheme in .launchpadrc required")
            Foundation.exit(1)
        }

        Logger.step("Fetching \(bid) v\(ver)")
        let appID = try await client.findApp(bundleID: bid)
        let versionID = try await client.getAppStoreVersion(appID: appID, version: ver)

        if let date {
            Logger.step("Scheduling release for \(date)")
        } else {
            Logger.step("Setting release to: after approval")
        }

        try await client.scheduleRelease(versionID: versionID, date: date)

        if let date {
            Logger.success("Release scheduled for \(date)")
        } else {
            Logger.success("Release set to automatic (after approval)")
        }
    }
}
