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
            IOSBuildsAssignGroupsCommand.self,
            IOSBuildsRemoveGroupsCommand.self,
            IOSBuildsIconsCommand.self,
            IOSBuildsResendInviteCommand.self,
            IOSBuildsCrashesCommand.self,
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

struct IOSBuildsAssignGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "assign-groups", abstract: "Add a build to one or more beta groups")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Option(name: .long, help: "Comma-separated beta group IDs")
    var groupIDs: String

    mutating func run() async throws {
        DotEnv.load()
        let ids = groupIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Assigning build \(buildID) to \(ids.count) group(s)")
        try await client.assignBuildToBetaGroups(buildID: buildID, groupIDs: ids)
        Logger.success("Build assigned to beta groups")
    }
}

struct IOSBuildsRemoveGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove-groups", abstract: "Remove a build from one or more beta groups")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Option(name: .long, help: "Comma-separated beta group IDs")
    var groupIDs: String

    mutating func run() async throws {
        DotEnv.load()
        let ids = groupIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Removing build \(buildID) from \(ids.count) group(s)")
        try await client.removeBuildFromBetaGroups(buildID: buildID, groupIDs: ids)
        Logger.success("Build removed from beta groups")
    }
}

struct IOSBuildsIconsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "icons", abstract: "Show build icons for a build")

    @Option(name: .long, help: "Build ID (from builds list)")
    var buildID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching icons for build \(buildID)")
        let icons = try await client.getBuildIcons(buildID: buildID)

        if icons.isEmpty { Logger.info("No icons found"); return }
        for icon in icons {
            guard let attrs = icon["attributes"] as? [String: Any] else { continue }
            let name  = attrs["iconAsset"] as? [String: Any]
            let url   = name?["url"] as? String ?? "-"
            let dim   = attrs["iconAsset"] as? [String: Any]
            let width = (dim?["width"] as? Int).map { "\($0)px" } ?? "-"
            print("  \(width)  \(url)")
        }
    }
}

struct IOSBuildsResendInviteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resend-invite", abstract: "Resend TestFlight invitation email to a beta tester")

    @Option(name: .long, help: "Beta tester ID (from beta groups list)")
    var testerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Resending TestFlight invitation to tester \(testerID)")
        try await client.resendBetaTestInvitation(testerID: testerID)
        Logger.success("Invitation resent")
    }
}

struct IOSBuildsCrashesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "crashes", abstract: "List crash/diagnostic signatures for a build")

    @Option(name: .long, help: "Build ID")
    var buildID: String

    @Option(name: .long, help: "Max number to show (default: 20)")
    var limit: Int = 20

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching diagnostic signatures for build \(buildID)")
        let crashes = try await client.getBuildCrashes(buildID: buildID, limit: limit)

        if crashes.isEmpty { Logger.info("No crash signatures found"); return }
        Logger.info("\(crashes.count) signature(s)\n")
        for c in crashes {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let signature = attrs["signature"] as? String ?? "-"
            let type_     = attrs["diagnosticType"] as? String ?? "-"
            let weight    = attrs["weight"] as? Double ?? 0
            print("  [\(type_)]  weight: \(weight)")
            print("    \(signature)")
            print("    id: \(id)\n")
        }
    }
}
