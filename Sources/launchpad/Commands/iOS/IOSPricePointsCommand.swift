import ArgumentParser
import Foundation

struct IOSPricePointsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "price-points",
        abstract: "Browse available price points and tiers",
        subcommands: [
            IOSPricePointsListCommand.self,
            IOSPriceTiersListCommand.self,
        ]
    )
}

struct IOSPricePointsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List price points for an app in a territory")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Territory code (e.g. USA, JPN)")
    var territory: String?

    @Option(name: .long, help: "Number of results to show (default: 30)")
    var limit: Int = 30

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching price points\(territory.map { " for \($0)" } ?? "")")
        let points = try await client.listPricePoints(appID: appID, territory: territory)
        let slice = Array(points.prefix(limit))

        if slice.isEmpty { Logger.info("No price points found"); return }
        Logger.info("Showing \(slice.count) price points\n")
        for p in slice {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let customerPrice = attrs["customerPrice"] as? String ?? "-"
            let proceeds      = attrs["proceeds"] as? String ?? "-"
            print("  id: \(id)  price: \(customerPrice)  proceeds: \(proceeds)")
        }
    }
}

struct IOSPriceTiersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tiers", abstract: "List all App Store price tiers")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching price tiers")
        let tiers = try await client.listPriceTiers()

        if tiers.isEmpty { Logger.info("No price tiers found"); return }
        Logger.info("\(tiers.count) tier(s)\n")
        for t in tiers {
            guard let id = t["id"] as? String else { continue }
            print("  Tier: \(id)")
        }
    }
}
