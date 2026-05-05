import ArgumentParser
import Foundation

struct IOSReviewsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviews",
        abstract: "Manage App Store customer reviews",
        subcommands: [
            IOSReviewsListCommand.self,
            IOSReviewsReplyCommand.self,
            IOSReviewsDeleteReplyCommand.self,
        ],
        defaultSubcommand: IOSReviewsListCommand.self
    )
}

// MARK: - list

struct IOSReviewsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show recent customer reviews"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Number of reviews to fetch (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching reviews for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let reviews = try await client.getCustomerReviews(appID: appID, limit: limit)

        if reviews.isEmpty { Logger.info("No reviews found"); return }

        Logger.info("Found \(reviews.count) review(s)\n")
        for review in reviews {
            guard let id = review["id"] as? String,
                  let attrs = review["attributes"] as? [String: Any] else { continue }
            let rating   = attrs["rating"] as? Int ?? 0
            let title    = attrs["title"] as? String ?? ""
            let body     = attrs["body"] as? String ?? ""
            let reviewer = attrs["reviewerNickname"] as? String ?? "Anonymous"
            let date     = attrs["createdDate"] as? String ?? ""
            let stars    = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
            print("[\(stars)] \(title)  id: \(id)")
            print("  \(body)")
            print("  — \(reviewer)  \(date)")

            if let response = (review["relationships"] as? [String: Any])?["response"] as? [String: Any],
               let respData = response["data"] as? [String: Any],
               let respID = respData["id"] as? String {
                print("  [Dev reply id: \(respID)]")
            }
            print()
        }
    }
}

// MARK: - reply

struct IOSReviewsReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Post or update a reply to a customer review"
    )

    @Option(name: .long, help: "Review ID (from reviews list)")
    var reviewID: String

    @Option(name: .long, help: "Reply text")
    var body: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Replying to review \(reviewID)")
        try await client.replyToReview(reviewID: reviewID, body: body)
        Logger.success("Reply posted")
    }
}

// MARK: - delete-reply

struct IOSReviewsDeleteReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-reply",
        abstract: "Delete a developer reply to a review"
    )

    @Option(name: .long, help: "Response ID (shown in reviews list)")
    var responseID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Deleting reply \(responseID)")
        try await client.deleteReviewResponse(responseID: responseID)
        Logger.success("Reply deleted")
    }
}
