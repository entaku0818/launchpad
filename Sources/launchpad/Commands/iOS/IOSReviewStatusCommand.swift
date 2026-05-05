import ArgumentParser
import Foundation

struct IOSReviewStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-status",
        abstract: "Show App Store review submission status"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        Logger.step("Fetching review submissions for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let submissions = try await client.getReviewSubmissions(appID: appID)

        if submissions.isEmpty {
            Logger.info("No active review submissions found")
            return
        }

        for sub in submissions {
            guard let attrs = sub["attributes"] as? [String: Any] else { continue }
            let state = attrs["state"] as? String ?? "UNKNOWN"
            let submitted = attrs["submittedDate"] as? String ?? "-"
            let platform = attrs["platform"] as? String ?? "-"
            let stateDisplay = stateLabel(state)
            print("\(stateDisplay)  platform: \(platform)  submitted: \(submitted)")
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "READY_FOR_REVIEW":     return "● Ready for Review"
        case "WAITING_FOR_REVIEW":   return "⏳ Waiting for Review"
        case "IN_REVIEW":            return "🔍 In Review"
        case "APPROVED":             return "✅ Approved"
        case "REJECTED":             return "✗ Rejected"
        case "DEVELOPER_REJECTED":   return "↩ Developer Rejected"
        case "CANCELLED":            return "✗ Cancelled"
        default:                     return "● \(state)"
        }
    }
}
