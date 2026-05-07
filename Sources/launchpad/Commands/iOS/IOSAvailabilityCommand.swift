import ArgumentParser
import Foundation

struct IOSAvailabilityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "availability",
        abstract: "Manage which territories the app is available in",
        subcommands: [
            IOSAvailabilityListCommand.self,
            IOSAvailabilitySetCommand.self,
        ]
    )
}

struct IOSAvailabilityListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List territories where the app is available")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching available territories for \(bid)")
        let territories = try await client.getAvailableTerritories(appID: appID)

        if territories.isEmpty { Logger.info("No territory data found"); return }
        let codes = territories.compactMap { $0["id"] as? String }.sorted()
        Logger.info("\(codes.count) territory/territories available\n")
        let chunks = stride(from: 0, to: codes.count, by: 8).map { Array(codes[$0..<min($0 + 8, codes.count)]) }
        for chunk in chunks {
            print("  " + chunk.joined(separator: "  "))
        }
    }
}

struct IOSAvailabilitySetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set available territories (replaces existing list)")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Comma-separated territory codes (e.g. USA,JPN,GBR)")
    var territories: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let codes = territories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Setting \(codes.count) territory/territories for \(bid)")
        try await client.setAvailableTerritories(appID: appID, territoryCodes: codes)
        Logger.success("Available territories updated")
    }
}
