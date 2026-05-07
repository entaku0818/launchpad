import ArgumentParser
import Foundation

struct IOSReviewStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-status",
        abstract: "Manage App Store review submissions",
        subcommands: [
            IOSReviewStatusListCommand.self,
            IOSReviewStatusCreateCommand.self,
            IOSReviewStatusCancelCommand.self,
        ]
    )
}

struct IOSReviewStatusListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Show App Store review submission status")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching review submissions for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let submissions = try await client.getReviewSubmissions(appID: appID)

        if submissions.isEmpty {
            Logger.info("No active review submissions found")
            return
        }

        for sub in submissions {
            guard let id = sub["id"] as? String,
                  let attrs = sub["attributes"] as? [String: Any] else { continue }
            let state    = attrs["state"] as? String ?? "UNKNOWN"
            let submitted = attrs["submittedDate"] as? String ?? "-"
            let platform = attrs["platform"] as? String ?? "-"
            print("  \(stateLabel(state))  platform: \(platform)  submitted: \(submitted)")
            print("    id: \(id)")
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "READY_FOR_REVIEW":     return "● Ready for Review"
        case "WAITING_FOR_REVIEW":   return "⏳ Waiting for Review"
        case "IN_REVIEW":            return "🔍 In Review"
        case "APPROVED":             return "✓ Approved"
        case "REJECTED":             return "✗ Rejected"
        case "DEVELOPER_REJECTED":   return "↩ Developer Rejected"
        case "CANCELLED":            return "✗ Cancelled"
        default:                     return "● \(state)"
        }
    }
}

struct IOSReviewStatusCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new review submission")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Platform: IOS, MAC_OS, TV_OS (default: IOS)")
    var platform: String = "IOS"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating review submission for \(bid) [\(platform)]")
        let id = try await client.createReviewSubmission(appID: appID, platform: platform)
        Logger.success("Review submission created: \(id)")
    }
}

struct IOSReviewStatusCancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cancel", abstract: "Cancel a review submission")

    @Option(name: .long, help: "Review submission ID (from review-status list)")
    var submissionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Cancelling review submission \(submissionID)")
        try await client.cancelReviewSubmission(submissionID: submissionID)
        Logger.success("Review submission cancelled")
    }
}
