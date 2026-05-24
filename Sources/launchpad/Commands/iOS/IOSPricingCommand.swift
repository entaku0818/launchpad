import ArgumentParser
import Foundation

struct IOSPricingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pricing",
        abstract: "View App Store pricing and territory availability",
        subcommands: [
            IOSPricingShowCommand.self,
            IOSPricingTerritoriesCommand.self,
            IOSPricingSetCommand.self,
            IOSPricingSetFreeCommand.self,
        ]
    )
}

// MARK: - show

struct IOSPricingShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current price schedule"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching price schedule for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let schedule = try await client.getPriceSchedule(appID: appID)

        guard let attrs = schedule["attributes"] as? [String: Any] else {
            Logger.info("No price schedule found"); return
        }

        if let manual = attrs["manualPrices"] as? [[String: Any]], !manual.isEmpty {
            print("\nManual Prices:")
            for p in manual {
                let territory = p["territory"] as? String ?? "-"
                let startDate = p["startDate"] as? String ?? "now"
                let customerPrice = p["customerPrice"] as? String ?? "-"
                let currency = p["proceeds"] as? String ?? ""
                print("  \(territory)  \(customerPrice) \(currency)  (from \(startDate))")
            }
        }

        if let included = schedule["relationships"] as? [String: Any],
           let base = included["baseTerritories"] as? [String: Any],
           let data = base["data"] as? [[String: Any]] {
            print("\nBase Territory: \(data.first?["id"] as? String ?? "-")")
        }
    }
}

// MARK: - territories

struct IOSPricingTerritoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "territories",
        abstract: "List available sale territories"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching available territories for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let territories = try await client.getAvailableTerritories(appID: appID)

        if territories.isEmpty { Logger.info("No territories found"); return }

        Logger.info("\(territories.count) territory/territories available\n")
        let codes = territories.compactMap { ($0["id"] as? String) }
        let joined = codes.chunks(ofCount: 10).map { $0.joined(separator: "  ") }.joined(separator: "\n")
        print(joined)
    }
}

// MARK: - set

struct IOSPricingSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set the app price using a price point ID"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Price point ID (from ios price-points list)")
    var pricePointID: String

    @Option(name: .long, help: "Effective start date (YYYY-MM-DD). Omit for immediate.")
    var startDate: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Setting price to point \(pricePointID) for \(bid)")
        try await client.setAppPriceSchedule(appID: appID, pricePointID: pricePointID, startDate: startDate)
        Logger.success("Price updated")
    }
}

struct IOSPricingSetFreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-free", abstract: "Set app price to free (no cost to users)")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Setting \(bid) as free")
        try await client.setAppFree(appID: appID)
        Logger.success("App price set to free")
    }
}

private extension Array {
    func chunks(ofCount size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
