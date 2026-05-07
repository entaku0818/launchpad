import ArgumentParser
import Foundation

struct IOSGameCenterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "game-center",
        abstract: "Manage Game Center leaderboards and achievements",
        subcommands: [
            IOSGameCenterLeaderboardsListCommand.self,
            IOSGameCenterLeaderboardsCreateCommand.self,
            IOSGameCenterLeaderboardsDeleteCommand.self,
            IOSGameCenterAchievementsListCommand.self,
            IOSGameCenterAchievementsCreateCommand.self,
            IOSGameCenterAchievementsDeleteCommand.self,
        ]
    )
}

struct IOSGameCenterLeaderboardsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "leaderboards-list", abstract: "List Game Center leaderboards")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching leaderboards")
        let boards = try await client.listLeaderboards(appID: appID)

        if boards.isEmpty { Logger.info("No leaderboards found"); return }
        Logger.info("\(boards.count) leaderboard(s)\n")
        for b in boards {
            guard let id = b["id"] as? String,
                  let attrs = b["attributes"] as? [String: Any] else { continue }
            let name = attrs["referenceName"] as? String ?? "-"
            let sort = attrs["scoreSortType"] as? String ?? "-"
            print("  \(name)  sort: \(sort)  id: \(id)")
        }
    }
}

struct IOSGameCenterLeaderboardsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "leaderboards-create", abstract: "Create a Game Center leaderboard")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Reference name (also used as vendorIdentifier)")
    var referenceName: String

    @Option(name: .long, help: "Default formatter: INTEGER, FIXED_POINT, ELAPSED_TIME_MILLISECONDS, ELAPSED_TIME_MINUTES_SECONDS, ELAPSED_TIME_HOURS_MINUTES_SECONDS, MONEY")
    var formatter: String = "INTEGER"

    @Option(name: .long, help: "Sort type: ASC or DESC")
    var sort: String = "DESC"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating leaderboard '\(referenceName)'")
        let id = try await client.createLeaderboard(appID: appID, referenceName: referenceName, defaultFormatter: formatter, scoreSortType: sort)
        Logger.success("Leaderboard created: \(id)")
    }
}

struct IOSGameCenterLeaderboardsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "leaderboards-delete", abstract: "Delete a Game Center leaderboard")

    @Option(name: .long, help: "Leaderboard ID")
    var leaderboardID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting leaderboard \(leaderboardID)")
        try await client.deleteLeaderboard(leaderboardID: leaderboardID)
        Logger.success("Leaderboard deleted")
    }
}

struct IOSGameCenterAchievementsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "achievements-list", abstract: "List Game Center achievements")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching achievements")
        let achievements = try await client.listAchievements(appID: appID)

        if achievements.isEmpty { Logger.info("No achievements found"); return }
        Logger.info("\(achievements.count) achievement(s)\n")
        for a in achievements {
            guard let id = a["id"] as? String,
                  let attrs = a["attributes"] as? [String: Any] else { continue }
            let name    = attrs["referenceName"] as? String ?? "-"
            let points  = attrs["points"] as? Int ?? 0
            let repeat_ = attrs["repeatable"] as? Bool ?? false
            print("  \(name)  points: \(points)  repeatable: \(repeat_)  id: \(id)")
        }
    }
}

struct IOSGameCenterAchievementsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "achievements-create", abstract: "Create a Game Center achievement")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Reference name")
    var referenceName: String

    @Option(name: .long, help: "Point value (1-100)")
    var points: Int = 10

    @Flag(name: .long, help: "Allow earning multiple times")
    var repeatable: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating achievement '\(referenceName)' (\(points) pts)")
        let id = try await client.createAchievement(appID: appID, referenceName: referenceName, points: points, repeatable: repeatable)
        Logger.success("Achievement created: \(id)")
    }
}

struct IOSGameCenterAchievementsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "achievements-delete", abstract: "Delete a Game Center achievement")

    @Option(name: .long, help: "Achievement ID")
    var achievementID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting achievement \(achievementID)")
        try await client.deleteAchievement(achievementID: achievementID)
        Logger.success("Achievement deleted")
    }
}
