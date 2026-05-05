import ArgumentParser
import Foundation

struct IOSSubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit app for App Store review via ASC API"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Xcode project path [config: ios.project]")
    var project: String?

    @Option(name: .long, help: "Target name [config: ios.scheme]")
    var target: String?

    @Option(name: .long, help: "App version (auto-read from xcodeproj if omitted)")
    var version: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios

        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId in .launchpadrc required"); Foundation.exit(1) }()
        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        let ver: String
        if let version {
            ver = version
        } else if let proj = project ?? cfg?.project, let tgt = target ?? cfg?.scheme {
            Logger.info("Reading version from \(proj)...")
            ver = try XcodeProject.versionNumber(project: proj, target: tgt)
        } else {
            Logger.error("--version or ios.project + ios.scheme in .launchpadrc required")
            Foundation.exit(1)
        }

        Logger.step("Finding app \(bid) v\(ver)")
        let appID = try await client.findApp(bundleID: bid)

        Logger.info("Finding App Store version...")
        let versionID = try await client.getAppStoreVersion(appID: appID, version: ver)

        Logger.step("Submitting for review")
        try await client.submitForReview(versionID: versionID)

        Logger.success("\(bid) v\(ver) submitted for review!")
    }
}
