import ArgumentParser
import Foundation

struct IOSClipsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clips",
        abstract: "List App Clips and their default experiences",
        subcommands: [
            IOSClipsListCommand.self,
            IOSClipsExperiencesCommand.self,
        ]
    )
}

struct IOSClipsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List App Clips for this app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching App Clips for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let clips = try await client.getAppClips(appID: appID)

        if clips.isEmpty { Logger.info("No App Clips found"); return }
        Logger.info("\(clips.count) App Clip(s)\n")
        for c in clips {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let bundleId = attrs["bundleId"] as? String ?? "-"
            print("  \(bundleId)  id: \(id)")
        }
    }
}

struct IOSClipsExperiencesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "experiences", abstract: "List default experiences for an App Clip")

    @Option(name: .long, help: "App Clip ID (from clips list)")
    var clipID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching experiences for App Clip \(clipID)")
        let experiences = try await client.getAppClipExperiences(appClipID: clipID)

        if experiences.isEmpty { Logger.info("No experiences found"); return }
        for e in experiences {
            guard let id = e["id"] as? String,
                  let attrs = e["attributes"] as? [String: Any] else { continue }
            let action    = attrs["action"] as? String ?? "-"
            let isPowered = attrs["isPoweredBy"] as? Bool ?? false
            print("  id: \(id)  action: \(action)  poweredByAppClip: \(isPowered)")
        }
    }
}
