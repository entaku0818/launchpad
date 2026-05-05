import ArgumentParser
import Foundation

struct IOSBuildsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builds",
        abstract: "List and inspect TestFlight builds",
        subcommands: [
            IOSBuildsListCommand.self,
            IOSBuildsGetCommand.self,
        ]
    )
}

struct IOSBuildsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recent builds")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Number of builds to show (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching builds for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let builds = try await client.listBuilds(appID: appID, limit: limit)

        if builds.isEmpty { Logger.info("No builds found"); return }
        Logger.info("\(builds.count) build(s)\n")
        for b in builds {
            guard let id = b["id"] as? String,
                  let attrs = b["attributes"] as? [String: Any] else { continue }
            let buildNum  = attrs["version"] as? String ?? "-"
            let state     = attrs["processingState"] as? String ?? "-"
            let uploaded  = attrs["uploadedDate"] as? String ?? "-"
            let minOS     = attrs["minOsVersion"] as? String ?? "-"
            let stateIcon = processingIcon(state)
            print("  \(stateIcon) build \(buildNum)  minOS: \(minOS)  uploaded: \(uploaded)")
            print("    id: \(id)\n")
        }
    }

    private func processingIcon(_ state: String) -> String {
        switch state {
        case "PROCESSING":           return "⏳"
        case "FAILED":               return "✗"
        case "INVALID":              return "✗"
        case "VALID":                return "✓"
        default:                     return "●"
        }
    }
}

struct IOSBuildsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show details of a build")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching build \(buildID)")
        let build = try await client.getBuild(buildID: buildID)

        guard let attrs = build["attributes"] as? [String: Any] else {
            Logger.error("Build not found"); Foundation.exit(1)
        }
        let buildNum = attrs["version"] as? String ?? "-"
        let state    = attrs["processingState"] as? String ?? "-"
        let uploaded = attrs["uploadedDate"] as? String ?? "-"
        let minOS    = attrs["minOsVersion"] as? String ?? "-"

        print("\nbuild number:     \(buildNum)")
        print("processingState:  \(state)")
        print("uploadedDate:     \(uploaded)")
        print("minOsVersion:     \(minOS)")
    }
}
