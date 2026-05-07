import ArgumentParser
import Foundation

struct IOSBetaFeedbackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "beta-feedback",
        abstract: "View TestFlight tester feedback and crash reports",
        subcommands: [
            IOSBetaFeedbackListCommand.self,
            IOSBetaCrashesCommand.self,
        ]
    )
}

struct IOSBetaFeedbackListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List TestFlight tester feedback screenshots and comments")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Number of entries to show (default: 20)")
    var limit: Int = 20

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching beta feedback for \(bid)")
        let feedback = try await client.getBetaFeedback(appID: appID, limit: limit)

        if feedback.isEmpty { Logger.info("No feedback found"); return }
        Logger.info("\(feedback.count) feedback item(s)\n")
        for f in feedback {
            guard let id = f["id"] as? String,
                  let attrs = f["attributes"] as? [String: Any] else { continue }
            let timestamp  = attrs["timestamp"] as? String ?? "-"
            let comment    = attrs["comment"] as? String ?? ""
            let deviceModel = attrs["deviceModel"] as? String ?? "-"
            let osVersion   = attrs["osVersion"] as? String ?? "-"
            print("  [\(timestamp)] \(deviceModel) iOS \(osVersion)")
            print("    id: \(id)")
            if !comment.isEmpty { print("    comment: \(comment)") }
            print("")
        }
    }
}

struct IOSBetaCrashesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "crashes", abstract: "List crash diagnostic signatures for a build")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Option(name: .long, help: "Number of signatures to show (default: 20)")
    var limit: Int = 20

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching crash signatures for build \(buildID)")
        let crashes = try await client.getBuildCrashes(buildID: buildID, limit: limit)

        if crashes.isEmpty { Logger.info("No crash signatures found"); return }
        Logger.info("\(crashes.count) signature(s)\n")
        for c in crashes {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let signatureType = attrs["diagnosticType"] as? String ?? "-"
            let signature     = attrs["signature"] as? String ?? "-"
            let weight        = attrs["weight"] as? Double ?? 0
            print("  \(signatureType): \(signature)")
            print("    id: \(id)  weight: \(weight)\n")
        }
    }
}
