import ArgumentParser
import Foundation

struct IOSReviewsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviews",
        abstract: "Show recent customer reviews from the App Store"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Number of reviews to fetch (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        Logger.step("Fetching reviews for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let reviews = try await client.getCustomerReviews(appID: appID, limit: limit)

        if reviews.isEmpty {
            Logger.info("No reviews found")
            return
        }

        Logger.info("Found \(reviews.count) review(s)\n")
        for review in reviews {
            guard let attrs = review["attributes"] as? [String: Any] else { continue }
            let rating = attrs["rating"] as? Int ?? 0
            let title = attrs["title"] as? String ?? ""
            let body = attrs["body"] as? String ?? ""
            let reviewer = attrs["reviewerNickname"] as? String ?? "Anonymous"
            let date = attrs["createdDate"] as? String ?? ""
            let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
            print("[\(stars)] \(title)")
            print("  \(body)")
            print("  — \(reviewer)  \(date)\n")
        }
    }
}
