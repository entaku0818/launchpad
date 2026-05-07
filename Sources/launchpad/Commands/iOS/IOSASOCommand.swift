import ArgumentParser
import Foundation

struct IOSASOCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aso",
        abstract: "App Store Optimization: keyword ranks, suggestions, metadata checks, and review insights",
        subcommands: [
            IOSASOKeywordRankCommand.self,
            IOSASOKeywordSuggestionsCommand.self,
            IOSASOKeywordReportCommand.self,
            IOSASOMetadataCheckCommand.self,
            IOSASOReviewSummaryCommand.self,
        ]
    )
}

// MARK: - keyword-rank

struct IOSASOKeywordRankCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyword-rank",
        abstract: "Check your app's search rank for given keywords via iTunes Search API"
    )

    @Option(name: .long, help: "Bundle ID of your app")
    var bundleID: String?

    @Option(name: .long, help: "Comma-separated keywords to check (e.g. \"英語学習,語学,TOEIC\")")
    var keywords: String

    @Option(name: .long, help: "Country code (default: jp)")
    var country: String = "jp"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId in .launchpadrc required"); Foundation.exit(1) }()

        let kwList = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !kwList.isEmpty else { Logger.error("--keywords must not be empty"); Foundation.exit(1) }

        let client = iTunesSearchClient()
        Logger.step("Checking keyword ranks for \(bid) in \"\(country)\" (\(kwList.count) keyword(s))")
        Logger.info("This may take a moment due to rate limiting...\n")

        let results = try await client.keywordRank(bundleID: bid, keywords: kwList, country: country)

        var found = 0
        for r in results {
            if let rank = r.rank {
                found += 1
                let bar = rank <= 10 ? "🟢" : rank <= 50 ? "🟡" : "🔴"
                print("  \(bar) #\(rank)  \(r.keyword)")
            } else {
                print("  ⬜ >200  \(r.keyword)")
            }
        }
        print("")
        Logger.info("Ranking in top 200: \(found)/\(results.count) keyword(s)")
        if found < results.count {
            Logger.info("Keywords not in top 200 may need to be added to your metadata or targeted via Search Ads.")
        }
    }
}

// MARK: - keyword-suggestions

struct IOSASOKeywordSuggestionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyword-suggestions",
        abstract: "Get keyword suggestions from Apple Search Ads based on your app or a competitor"
    )

    @Option(name: .long, help: "Your app's Adam ID (numeric App Store ID)")
    var adamID: Int

    @Option(name: .long, parsing: .upToNextOption, help: "Competitor app Adam IDs (optional)")
    var competitorIDs: [Int] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Country codes (default: JP)")
    var countries: [String] = ["JP"]

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = SearchAdsClient(credentials: try SearchAdsCredentials.fromEnvironment(), orgID: orgID)
        Logger.step("Fetching keyword suggestions for Adam ID \(adamID)")

        let suggestions = try await client.keywordSuggestions(adamID: adamID, countryCodes: countries, competitorAdamIDs: competitorIDs)

        if suggestions.isEmpty { Logger.info("No suggestions returned"); return }

        Logger.info("\(suggestions.count) keyword suggestion(s)\n")
        let sorted = suggestions.sorted {
            let a = ($0["searchTermsImpressionsShare"] as? Double) ?? 0
            let b = ($1["searchTermsImpressionsShare"] as? Double) ?? 0
            return a > b
        }
        for s in sorted {
            let text   = s["text"] as? String ?? "-"
            let share  = (s["searchTermsImpressionsShare"] as? Double).map { String(format: "%.1f%%", $0 * 100) } ?? "-"
            let bidMin = ((s["bidRecommendation"] as? [String: Any])?["bidMin"] as? [String: Any])?["amount"] as? String ?? "-"
            let bidMax = ((s["bidRecommendation"] as? [String: Any])?["bidMax"] as? [String: Any])?["amount"] as? String ?? "-"
            print("  \"\(text)\"  share: \(share)  suggested bid: \(bidMin)–\(bidMax)")
        }
        print("")
        Logger.info("Tip: Add high-share keywords with low bids to your metadata keywords field.")
    }
}

// MARK: - keyword-report

struct IOSASOKeywordReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyword-report",
        abstract: "Analyze Search Ads keyword performance with ASO-focused insights"
    )

    @Option(name: .long, help: "Campaign ID to analyze")
    var campaignID: Int

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var startDate: String

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var endDate: String

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = SearchAdsClient(credentials: try SearchAdsCredentials.fromEnvironment(), orgID: orgID)
        Logger.step("Fetching keyword report for campaign \(campaignID)")

        let result = try await client.reportKeywords(campaignID: campaignID, startDate: startDate, endDate: endDate)
        let rows = (result["data"] as? [String: Any])
            .flatMap { $0["reportingDataResponse"] as? [String: Any] }
            .flatMap { $0["row"] as? [[String: Any]] } ?? []

        if rows.isEmpty { Logger.info("No keyword data found for this period"); return }

        struct KWRow {
            let keyword: String
            let matchType: String
            let impressions: Int
            let taps: Int
            let installs: Int
            let spend: Double
        }

        var kwRows: [KWRow] = []
        for row in rows {
            let meta       = row["metadata"] as? [String: Any] ?? [:]
            let totals     = row["total"] as? [String: Any] ?? [:]
            let keyword    = meta["keyword"] as? String ?? meta["keywordId"] as? String ?? "-"
            let matchType  = meta["matchType"] as? String ?? "-"
            let impressions = totals["impressions"] as? Int ?? 0
            let taps        = totals["taps"] as? Int ?? 0
            let installs    = totals["installs"] as? Int ?? 0
            let spendStr    = (totals["localSpend"] as? [String: Any])?["amount"] as? String ?? "0"
            let spend       = Double(spendStr) ?? 0
            kwRows.append(KWRow(keyword: keyword, matchType: matchType, impressions: impressions, taps: taps, installs: installs, spend: spend))
        }

        let sorted = kwRows.sorted { $0.impressions > $1.impressions }

        print("  \("Keyword".padding(toLength: 30, withPad: " ", startingAt: 0))  Match   Imp    Taps  Install  Spend   Advice")
        print("  " + String(repeating: "-", count: 90))

        for kw in sorted {
            let ttr  = kw.impressions > 0 ? Double(kw.taps) / Double(kw.impressions) * 100 : 0
            let cvr  = kw.taps > 0 ? Double(kw.installs) / Double(kw.taps) * 100 : 0
            let cpi  = kw.installs > 0 ? kw.spend / Double(kw.installs) : 0

            var advice = ""
            if kw.impressions < 100 {
                advice = "Low volume — consider adding to metadata"
            } else if ttr < 3 {
                advice = "Low TTR (\(String(format: "%.1f", ttr))%) — improve icon/title"
            } else if cvr < 30 && kw.taps >= 10 {
                advice = "Low CVR (\(String(format: "%.1f", cvr))%) — review store page"
            } else if kw.installs > 5 && cpi < 500 {
                advice = "High performer — add to keywords field"
            }

            let name = kw.keyword.padding(toLength: 30, withPad: " ", startingAt: 0)
            let match = kw.matchType.padding(toLength: 6, withPad: " ", startingAt: 0)
            print("  \(name)  \(match)  \(String(format: "%5d", kw.impressions))  \(String(format: "%5d", kw.taps))  \(String(format: "%5d", kw.installs))  \(String(format: "%6.0f", kw.spend))")
            if !advice.isEmpty {
                print("    → \(advice)")
            }
        }
        print("")

        let totalSpend    = kwRows.reduce(0.0) { $0 + $1.spend }
        let totalInstalls = kwRows.reduce(0) { $0 + $1.installs }
        let avgCPI        = totalInstalls > 0 ? totalSpend / Double(totalInstalls) : 0
        Logger.info("Total spend: \(String(format: "%.2f", totalSpend))  Total installs: \(totalInstalls)  Avg CPI: \(String(format: "%.2f", avgCPI))")
    }
}

// MARK: - metadata-check

struct IOSASOMetadataCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata-check",
        abstract: "Validate fastlane/metadata/ files against App Store character limits and ASO best practices"
    )

    @Option(name: .long, help: "Path to metadata directory (default: fastlane/metadata)")
    var metadataDir: String = "fastlane/metadata"

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
            let maxBytes: Int
        }

        let rules: [Rule] = [
            Rule(file: "name.txt",             label: "Title",            maxBytes: 30),
            Rule(file: "subtitle.txt",          label: "Subtitle",         maxBytes: 30),
            Rule(file: "keywords.txt",          label: "Keywords",         maxBytes: 100),
            Rule(file: "description.txt",       label: "Description",      maxBytes: 4000),
            Rule(file: "promotional_text.txt",  label: "Promotional text", maxBytes: 170),
            Rule(file: "release_notes.txt",     label: "Release notes",    maxBytes: 4000),
        ]

        var totalIssues = 0

        for locale in localeDirs {
            let localeDir = "\(metadataDir)/\(locale)"
            var localeIssues: [String] = []

            // character limit checks
            for rule in rules {
                let filePath = "\(localeDir)/\(rule.file)"
                guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let byteCount = trimmed.utf8.count
                if byteCount > rule.maxBytes {
                    localeIssues.append("\(rule.label): \(byteCount) bytes (max \(rule.maxBytes)) — trim \(byteCount - rule.maxBytes) byte(s)")
                }
            }

            // keyword duplication check: words in title should not waste keyword slots
            let titlePath    = "\(localeDir)/name.txt"
            let keywordsPath = "\(localeDir)/keywords.txt"
            if let title = try? String(contentsOfFile: titlePath, encoding: .utf8),
               let kwText = try? String(contentsOfFile: keywordsPath, encoding: .utf8) {
                let titleWords = Set(title.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
                let kwWords    = kwText.lowercased().components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let duplicates = kwWords.filter { titleWords.contains($0) }
                if !duplicates.isEmpty {
                    localeIssues.append("Keywords duplicate title words (wasted space): \(duplicates.joined(separator: ", "))")
                }
            }

            // subtitle duplication with keywords
            let subtitlePath = "\(localeDir)/subtitle.txt"
            if let subtitle = try? String(contentsOfFile: subtitlePath, encoding: .utf8),
               let kwText = try? String(contentsOfFile: keywordsPath, encoding: .utf8) {
                let subtitleWords = Set(subtitle.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
                let kwWords       = kwText.lowercased().components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let duplicates    = kwWords.filter { subtitleWords.contains($0) }
                if !duplicates.isEmpty {
                    localeIssues.append("Keywords duplicate subtitle words (wasted space): \(duplicates.joined(separator: ", "))")
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
            Logger.info("Fix the issues above before submitting to avoid rejection or lost keyword coverage.")
        }
    }
}

// MARK: - review-summary

struct IOSASOReviewSummaryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-summary",
        abstract: "Aggregate customer reviews by rating and surface common themes"
    )

    @Option(name: .long, help: "Bundle ID of your app")
    var bundleID: String?

    @Option(name: .long, help: "Number of recent reviews to analyze (default: 200)")
    var limit: Int = 200

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId in .launchpadrc required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching up to \(limit) reviews for \(bid)")

        let appID   = try await client.findApp(bundleID: bid)
        let reviews = try await client.getCustomerReviews(appID: appID, limit: limit)

        if reviews.isEmpty { Logger.info("No reviews found"); return }

        // rating distribution
        var ratingCounts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        var allWords: [String: Int] = [:]
        var negativeWords: [String: Int] = [:]

        let stopWords: Set<String> = ["the", "a", "an", "is", "it", "in", "on", "at", "to", "for", "of", "and", "or", "but",
                                       "this", "that", "with", "my", "i", "me", "you", "your", "we", "app", "apps",
                                       "have", "has", "was", "are", "be", "been", "not", "no", "so", "if", "as",
                                       "do", "did", "can", "would", "could", "will", "just", "very", "really",
                                       "good", "great", "love", "like", "use", "using", "used", "get", "got"]

        for review in reviews {
            guard let attrs = review["attributes"] as? [String: Any] else { continue }
            let rating = attrs["rating"] as? Int ?? 0
            if (1...5).contains(rating) { ratingCounts[rating, default: 0] += 1 }

            let body  = ((attrs["body"] as? String) ?? "").lowercased()
            let words = body.components(separatedBy: .init(charactersIn: " .,!?\"'()[]"))
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
            Logger.warn("Address the negative themes above — they likely impact your conversion rate.")
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
