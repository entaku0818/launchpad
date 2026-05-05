import ArgumentParser
import Foundation

struct IOSPhasedReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "phased-release",
        abstract: "Manage phased (staged) rollout for an App Store version"
    )

    enum Action: String, ExpressibleByArgument {
        case start, pause, resume, complete, cancel
    }

    @Argument(help: "Action: start | pause | resume | complete | cancel")
    var action: Action

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version (auto-read from xcodeproj if omitted)")
    var version: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

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
        let (versionID, _) = try await {
            do {
                let v = try await client.getAppStoreVersion(appID: appID, version: ver)
                return (v, ver)
            } catch {
                return try await client.getLatestEditableAppStoreVersion(appID: appID)
            }
        }()

        switch action {
        case .start:
            Logger.step("Starting phased release")
            if let existing = try await client.getPhasedRelease(versionID: versionID) {
                try await client.updatePhasedRelease(id: existing.id, state: "ACTIVE")
            } else {
                let id = try await client.createPhasedRelease(versionID: versionID)
                try await client.updatePhasedRelease(id: id, state: "ACTIVE")
            }
            Logger.success("Phased release started (1% → 2% → 5% → ... → 100% over 7 days)")

        case .pause:
            Logger.step("Pausing phased release")
            guard let existing = try await client.getPhasedRelease(versionID: versionID) else {
                Logger.error("No phased release found for this version")
                Foundation.exit(1)
            }
            try await client.updatePhasedRelease(id: existing.id, state: "PAUSED")
            Logger.success("Phased release paused")

        case .resume:
            Logger.step("Resuming phased release")
            guard let existing = try await client.getPhasedRelease(versionID: versionID) else {
                Logger.error("No phased release found for this version")
                Foundation.exit(1)
            }
            try await client.updatePhasedRelease(id: existing.id, state: "ACTIVE")
            Logger.success("Phased release resumed")

        case .complete:
            Logger.step("Completing phased release (100% rollout)")
            guard let existing = try await client.getPhasedRelease(versionID: versionID) else {
                Logger.error("No phased release found for this version")
                Foundation.exit(1)
            }
            try await client.updatePhasedRelease(id: existing.id, state: "COMPLETE")
            Logger.success("Phased release completed — 100% of users will receive the update")

        case .cancel:
            Logger.step("Cancelling phased release")
            guard let existing = try await client.getPhasedRelease(versionID: versionID) else {
                Logger.error("No phased release found for this version")
                Foundation.exit(1)
            }
            try await client.deletePhasedRelease(id: existing.id)
            Logger.success("Phased release cancelled")
        }
    }
}
