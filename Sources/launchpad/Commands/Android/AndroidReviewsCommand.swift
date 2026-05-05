import ArgumentParser
import Foundation

struct AndroidReviewsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviews",
        abstract: "List recent Play Store reviews and optionally reply"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of reviews to fetch (default: 10)")
    var limit: Int = 10

    @Option(name: .long, help: "Reply to a review by its ID")
    var replyTo: String?

    @Option(name: .long, help: "Reply text (required with --reply-to)")
    var replyText: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        if let reviewID = replyTo {
            guard let text = replyText, !text.isEmpty else {
                Logger.error("--reply-text is required with --reply-to")
                Foundation.exit(1)
            }
            Logger.step("Replying to review \(reviewID)")
            try await client.replyToReview(packageName: pkg, reviewID: reviewID, text: text)
            Logger.success("Reply posted")
            return
        }

        Logger.step("Fetching reviews for \(pkg)")
        let reviews = try await client.listReviews(packageName: pkg, limit: limit)

        if reviews.isEmpty {
            Logger.info("No reviews found")
            return
        }

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
