import ArgumentParser
import Foundation

struct AndroidReviewsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviews",
        abstract: "Manage Play Store reviews",
        subcommands: [
            AndroidReviewsListCommand.self,
            AndroidReviewsGetCommand.self,
            AndroidReviewsReplyCommand.self,
        ]
    )
}

struct AndroidReviewsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recent Play Store reviews")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of reviews to fetch (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching reviews for \(pkg)")
        let reviews = try await client.listReviews(packageName: pkg, limit: limit)

        if reviews.isEmpty { Logger.info("No reviews found"); return }
        Logger.info("Found \(reviews.count) review(s)\n")
        for review in reviews {
            let reviewID = review["reviewId"] as? String ?? "-"
            guard let comments = review["comments"] as? [[String: Any]],
                  let userComment = comments.first?["userComment"] as? [String: Any]
            else { continue }

            let rating = userComment["starRating"] as? Int ?? 0
            let text = userComment["text"] as? String ?? ""
            let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)

            print("[\(stars)] ID: \(reviewID)")
            print("  \(text)\n")

            if let devComment = comments.first?["developerComment"] as? [String: Any],
               let devText = devComment["text"] as? String {
                print("  [Dev reply] \(devText)\n")
            }
        }
    }
}

struct AndroidReviewsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get a specific review by ID")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Review ID")
    var reviewID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching review \(reviewID)")
        let review = try await client.getReview(packageName: pkg, reviewID: reviewID)

        let rid = review["reviewId"] as? String ?? reviewID
        guard let comments = review["comments"] as? [[String: Any]],
              let userComment = comments.first?["userComment"] as? [String: Any]
        else {
            Logger.info("No comment data found")
            return
        }

        let rating = userComment["starRating"] as? Int ?? 0
        let text = userComment["text"] as? String ?? ""
        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)

        print("ID: \(rid)")
        print("Rating: \(stars)")
        print("Text: \(text)")

        if let devComment = comments.first?["developerComment"] as? [String: Any],
           let devText = devComment["text"] as? String {
            print("Dev reply: \(devText)")
        }
    }
}

struct AndroidReviewsReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reply", abstract: "Reply to a review")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Review ID")
    var reviewID: String

    @Option(name: .long, help: "Reply text")
    var text: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Replying to review \(reviewID)")
        try await client.replyToReview(packageName: pkg, reviewID: reviewID, text: text)
        Logger.success("Reply posted")
    }
}
