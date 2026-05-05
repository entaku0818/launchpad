import ArgumentParser
import Foundation

struct IOSPromoCodesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "promo-codes",
        abstract: "List or generate App Store promotional codes",
        subcommands: [
            IOSPromoCodesListCommand.self,
            IOSPromoCodesCreateCommand.self,
        ]
    )
}

struct IOSPromoCodesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recent promo code batches")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching promo codes for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let codes = try await client.listPromoCodes(appID: appID)

        if codes.isEmpty { Logger.info("No promo code batches found"); return }
        Logger.info("\(codes.count) batch(es)\n")
        for c in codes {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let quantity     = attrs["numberOfCodes"] as? Int ?? 0
            let expirationDate = attrs["expirationDate"] as? String ?? "-"
            let version      = attrs["version"] as? String ?? "-"
            print("  id: \(id)  qty: \(quantity)  version: \(version)  expires: \(expirationDate)")
        }
    }
}

struct IOSPromoCodesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Generate a promo code batch")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Number of codes to generate (max 100 per request)")
    var quantity: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        guard quantity >= 1 && quantity <= 100 else {
            Logger.error("--quantity must be between 1 and 100"); Foundation.exit(1)
        }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating \(quantity) promo code(s) for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let result = try await client.createPromoCodes(appID: appID, quantity: quantity)

        if result.isEmpty {
            Logger.info("Request submitted — check 'promo-codes list' for the batch when ready")
        } else {
            Logger.success("Created \(result.count) promo code batch(es)")
        }
    }
}
