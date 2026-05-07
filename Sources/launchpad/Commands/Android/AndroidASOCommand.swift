import ArgumentParser
import Foundation

struct AndroidASOCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aso",
        abstract: "App Store Optimization: metadata checks and review insights for Google Play",
        subcommands: [
            AndroidASOMetadataCheckCommand.self,
            AndroidASOReviewSummaryCommand.self,
        ]
    )
}

// MARK: - metadata-check

struct AndroidASOMetadataCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata-check",
        abstract: "Validate fastlane/metadata/android/ files against Google Play character limits"
    )

    @Option(name: .long, help: "Path to Android metadata directory (default: fastlane/metadata/android)")
    var metadataDir: String = "fastlane/metadata/android"

    mutating func run() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metadataDir) else {
            Logger.error("Metadata directory not found: \(metadataDir)")
            Foundation.exit(1)
        }

        let locales = (try? fm.contentsOfDirectory(atPath: metadataDir)) ?? []
        let localeDirs = locales.filter {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: "\(metadataDir)/\($0)", isDirectory: &isDir)
            return isDir.boolValue && !$0.hasPrefix(".")
        }.sorted()

        if localeDirs.isEmpty { Logger.info("No locale directories found in \(metadataDir)"); return }

        struct Rule {
            let file: String
            let label: String
            let maxChars: Int
        }

        let rules: [Rule] = [
            Rule(file: "title.txt",             label: "Title",             maxChars: 50),
            Rule(file: "short_description.txt", label: "Short description", maxChars: 80),
            Rule(file: "full_description.txt",  label: "Full description",  maxChars: 4000),
        ]

        var totalIssues = 0

        for locale in localeDirs {
            let localeDir = "\(metadataDir)/\(locale)"
            var localeIssues: [String] = []

            for rule in rules {
                let filePath = "\(localeDir)/\(rule.file)"
                guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let charCount = trimmed.count
                if charCount > rule.maxChars {
                    localeIssues.append("\(rule.label): \(charCount) chars (max \(rule.maxChars)) — remove \(charCount - rule.maxChars) char(s)")
                }
            }

            // changelog check (changelogs/default.txt or changelogs/*.txt)
            let changelogDir = "\(localeDir)/changelogs"
            if let changelogs = try? fm.contentsOfDirectory(atPath: changelogDir) {
                for file in changelogs where file.hasSuffix(".txt") {
                    let path = "\(changelogDir)/\(file)"
                    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count > 500 {
                            localeIssues.append("Changelog \(file): \(trimmed.count) chars (max 500) — remove \(trimmed.count - 500) char(s)")
                        }
                    }
                }
            }

            // title should not be just the app name repeated in short_description
            let titlePath    = "\(localeDir)/title.txt"
            let shortDescPath = "\(localeDir)/short_description.txt"
            if let title = try? String(contentsOfFile: titlePath, encoding: .utf8),
               let shortDesc = try? String(contentsOfFile: shortDescPath, encoding: .utf8) {
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let s = shortDesc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !t.isEmpty && s.hasPrefix(t) {
                    localeIssues.append("Short description starts with the title — add unique value instead of repeating app name")
                }
            }

            if localeIssues.isEmpty {
                print("  ✓ \(locale)")
            } else {
                print("  ✗ \(locale)")
                for issue in localeIssues {
                    print("      · \(issue)")
                }
                totalIssues += localeIssues.count
            }
        }

        print("")
        if totalIssues == 0 {
            Logger.success("All metadata passed checks (\(localeDirs.count) locale(s))")
        } else {
            Logger.warn("\(totalIssues) issue(s) found across \(localeDirs.count) locale(s)")
            Logger.info("Google Play rejects uploads that exceed character limits.")
        }
    }
}

// MARK: - review-summary

struct AndroidASOReviewSummaryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-summary",
        abstract: "Aggregate Google Play reviews by rating and surface common themes"
    )

    @Option(name: .long, help: "Package name (e.g. com.example.app)")
    var packageName: String?

    @Option(name: .long, help: "Number of recent reviews to analyze (default: 200)")
    var limit: Int = 200

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName in .launchpadrc required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching up to \(limit) reviews for \(pkg)")
        let reviews = try await client.listReviews(packageName: pkg, limit: limit)

        if reviews.isEmpty { Logger.info("No reviews found"); return }

        var ratingCounts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        var allWords: [String: Int] = [:]
        var negativeWords: [String: Int] = [:]

        let stopWords: Set<String> = ["the", "a", "an", "is", "it", "in", "on", "at", "to", "for", "of", "and", "or", "but",
                                       "this", "that", "with", "my", "i", "me", "you", "your", "we", "app", "apps",
                                       "have", "has", "was", "are", "be", "been", "not", "no", "so", "if", "as",
                                       "do", "did", "can", "would", "could", "will", "just", "very", "really",
                                       "good", "great", "love", "like", "use", "using", "used", "get", "got"]

        for review in reviews {
            guard let comments = review["comments"] as? [[String: Any]],
                  let firstComment = comments.first,
                  let userComment = firstComment["userComment"] as? [String: Any] else { continue }

            let rating = userComment["starRating"] as? Int ?? 0
            if (1...5).contains(rating) { ratingCounts[rating, default: 0] += 1 }

            let text = ((userComment["text"] as? String) ?? "").lowercased()
            let words = text.components(separatedBy: CharacterSet(charactersIn: " .,!?\"'()[]"))
                            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                            .filter { $0.count >= 4 && !stopWords.contains($0) }

            for w in words {
                allWords[w, default: 0] += 1
                if rating <= 2 { negativeWords[w, default: 0] += 1 }
            }
        }

        let totalReviews = reviews.count
        let totalScore   = ratingCounts.reduce(0) { $0 + $1.key * $1.value }
        let avgRating    = totalReviews > 0 ? Double(totalScore) / Double(totalReviews) : 0

        print("  Reviews analyzed: \(totalReviews)  Average rating: \(String(format: "%.1f", avgRating)) ★\n")
        print("  Rating distribution:")
        for star in stride(from: 5, through: 1, by: -1) {
            let count = ratingCounts[star, default: 0]
            let pct   = totalReviews > 0 ? Int(Double(count) / Double(totalReviews) * 20) : 0
            let bar   = String(repeating: "█", count: pct) + String(repeating: "░", count: 20 - pct)
            print("    \(star)★  \(bar)  \(count)")
        }

        let topPositive = allWords
            .filter { negativeWords[$0.key, default: 0] == 0 }
            .sorted { $0.value > $1.value }
            .prefix(8)
        let topNegative = negativeWords
            .sorted { $0.value > $1.value }
            .prefix(8)

        if !topPositive.isEmpty {
            print("\n  Frequently mentioned positively:")
            for (w, c) in topPositive { print("    \"\(w)\" ×\(c)") }
        }
        if !topNegative.isEmpty {
            print("\n  Frequently mentioned in low-rated reviews:")
            for (w, c) in topNegative { print("    \"\(w)\" ×\(c)") }
            print("")
            Logger.warn("Address the negative themes above — they likely impact your store conversion rate.")
        }

        let negativeCount = ratingCounts[1, default: 0] + ratingCounts[2, default: 0]
        if negativeCount > 0 {
            let negPct = Int(Double(negativeCount) / Double(totalReviews) * 100)
            if negPct >= 20 {
                Logger.warn("\(negPct)% of reviews are 1–2 stars. Prioritize fixing the common complaints above.")
            }
        }
    }
}
