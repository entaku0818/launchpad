import ArgumentParser
import Foundation

struct IOSIAPPriceScheduleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap-price-schedule",
        abstract: "View and set price schedules for in-app purchases",
        subcommands: [
            IOSIAPPriceScheduleGetCommand.self,
            IOSIAPPriceScheduleListCommand.self,
            IOSIAPPriceScheduleSetCommand.self,
        ]
    )
}

struct IOSIAPPriceScheduleGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show the current price schedule for an IAP")

    @Option(name: .long, help: "In-app purchase ID (from ios iap list)")
    var iapID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching price schedule for IAP \(iapID)")
        let schedule = try await client.getIAPPriceSchedule(iapID: iapID)

        guard let id = schedule["id"] as? String else {
            Logger.info("No price schedule found"); return
        }
        print("Price schedule ID: \(id)")
        if let rels = schedule["relationships"] as? [String: Any],
           let base = rels["baseTerritory"] as? [String: Any],
           let baseData = base["data"] as? [String: Any],
           let territory = baseData["id"] as? String {
            print("Base territory:    \(territory)")
        }
    }
}

struct IOSIAPPriceScheduleListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List manual prices for an IAP")

    @Option(name: .long, help: "In-app purchase ID (from ios iap list)")
    var iapID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching prices for IAP \(iapID)")
        let prices = try await client.listIAPPrices(iapID: iapID)

        if prices.isEmpty { Logger.info("No manual prices set"); return }
        Logger.info("\(prices.count) price(s)\n")
        for p in prices {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let startDate = attrs["startDate"] as? String ?? "immediate"
            print("  id: \(id)  startDate: \(startDate)")
        }
    }
}

struct IOSIAPPriceScheduleSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a price for an IAP using a price point ID")

    @Option(name: .long, help: "In-app purchase ID (from ios iap list)")
    var iapID: String

    @Option(name: .long, help: "IAP price point ID (from ios price-points list)")
    var pricePointID: String

    @Option(name: .long, help: "Start date in ISO 8601 format (e.g. 2025-01-01), or omit for immediate")
    var startDate: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Setting price for IAP \(iapID)")
        try await client.setIAPPriceSchedule(iapID: iapID, pricePointID: pricePointID, startDate: startDate)
        Logger.success("IAP price schedule updated")
    }
}
