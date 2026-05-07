import ArgumentParser
import Foundation

struct IOSBuildsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builds",
        abstract: "List and inspect TestFlight builds",
        subcommands: [
            IOSBuildsListCommand.self,
            IOSBuildsGetCommand.self,
            IOSBuildsNotesCommand.self,
            IOSBuildsReviewCommand.self,
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

struct IOSBuildsNotesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "notes", abstract: "Set 'What to Test' notes for a build")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Option(name: .long, help: "Locale (e.g. en-US, ja)")
    var locale: String = "en-US"

    @Option(name: .long, help: "What to test text")
    var text: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching existing localizations for build \(buildID)")
        let locs = try await client.getBuildLocalizations(buildID: buildID)

        if let existing = locs.first(where: {
            ($0["attributes"] as? [String: Any])?["locale"] as? String == locale
        }), let locID = existing["id"] as? String {
            Logger.info("Updating existing '\(locale)' localization")
            try await client.updateBuildLocalization(localizationID: locID, whatsNew: text)
        } else {
            Logger.info("Creating new '\(locale)' localization")
            try await client.createBuildLocalization(buildID: buildID, locale: locale, whatsNew: text)
        }
        Logger.success("'What to Test' notes updated for \(locale)")
    }
}

struct IOSBuildsReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "review", abstract: "Submit a build for TestFlight beta review or check status")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Flag(name: .long, help: "Check review status instead of submitting")
    var status: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        if status {
            Logger.step("Checking beta review status for build \(buildID)")
            let state = try await client.getBetaReviewStatus(buildID: buildID)
            let icon = reviewIcon(state)
            print("\n  \(icon) \(state)")
        } else {
            Logger.step("Submitting build \(buildID) for TestFlight beta review")
            try await client.submitForBetaReview(buildID: buildID)
            Logger.success("Submitted for beta review")
        }
    }

    private func reviewIcon(_ state: String) -> String {
        switch state {
        case "WAITING_FOR_REVIEW": return "⏳"
        case "IN_REVIEW":          return "🔍"
        case "APPROVED":           return "✓"
        case "REJECTED":           return "✗"
        default:                   return "●"
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
