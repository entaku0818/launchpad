import ArgumentParser
import Foundation

struct IOSSubscriptionPricesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-prices",
        abstract: "Manage per-territory pricing for subscriptions",
        subcommands: [
            IOSSubPricesListCommand.self,
            IOSSubPricePointsCommand.self,
            IOSSubPricesSetCommand.self,
            IOSSubPricesDeleteCommand.self,
        ]
    )
}

struct IOSSubPricesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List current prices for a subscription")

    @Option(name: .long, help: "Subscription ID (from ios subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching prices for subscription \(subscriptionID)")
        let prices = try await client.listSubscriptionPrices(subscriptionID: subscriptionID)

        if prices.isEmpty { Logger.info("No prices found"); return }
        Logger.info("\(prices.count) price(s)\n")
        for p in prices {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let startDate = attrs["startDate"] as? String ?? "immediate"
            print("  id: \(id)  startDate: \(startDate)")
        }
    }
}

struct IOSSubPricePointsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "price-points", abstract: "List available price points for a subscription in a territory")

    @Option(name: .long, help: "Subscription ID (from ios subscription-groups products)")
    var subscriptionID: String

    @Option(name: .long, help: "Territory code (e.g. USA, JPN)")
    var territory: String?

    @Option(name: .long, help: "Maximum number of results to show (default: 30)")
    var limit: Int = 30

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching subscription price points\(territory.map { " for \($0)" } ?? "")")
        let points = try await client.listSubscriptionPricePoints(subscriptionID: subscriptionID, territory: territory)
        let slice = Array(points.prefix(limit))

        if slice.isEmpty { Logger.info("No price points found"); return }
        Logger.info("Showing \(slice.count) price point(s)\n")
        for p in slice {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let customerPrice = attrs["customerPrice"] as? String ?? "-"
            let proceeds      = attrs["proceeds"] as? String ?? "-"
            print("  id: \(id)  price: \(customerPrice)  proceeds: \(proceeds)")
        }
    }
}

struct IOSSubPricesSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a price for a subscription in a territory")

    @Option(name: .long, help: "Subscription ID (from ios subscription-groups products)")
    var subscriptionID: String

    @Option(name: .long, help: "Price point ID (from price-points)")
    var pricePointID: String

    @Option(name: .long, help: "Territory code (e.g. USA, JPN)")
    var territory: String

    @Option(name: .long, help: "Start date in ISO 8601 format, or omit for immediate")
    var startDate: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Setting subscription price for \(territory)")
        let id = try await client.createSubscriptionPrice(subscriptionID: subscriptionID, pricePointID: pricePointID, territory: territory, startDate: startDate)
        Logger.success("Subscription price set: \(id)")
    }
}

struct IOSSubPricesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription price entry")

    @Option(name: .long, help: "Subscription price ID (from list)")
    var priceID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting subscription price \(priceID)")
        try await client.deleteSubscriptionPrice(priceID: priceID)
        Logger.success("Subscription price deleted")
    }
}
