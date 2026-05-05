import ArgumentParser
import Foundation

struct AndroidOffersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "offers",
        abstract: "Manage subscription base plan offers (free trials, intro pricing)",
        subcommands: [
            AndroidOffersListCommand.self,
            AndroidOffersActivateCommand.self,
        ]
    )
}

struct AndroidOffersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List offers for a base plan")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    @Option(name: .long, help: "Base plan ID")
    var basePlanID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching offers for \(productID)/\(basePlanID)")
        let offers = try await client.listSubscriptionOffers(packageName: pkg, productID: productID, basePlanID: basePlanID)

        if offers.isEmpty { Logger.info("No offers found"); return }
        Logger.info("\(offers.count) offer(s)\n")
        for o in offers {
            let offerID = o["offerId"] as? String ?? "-"
            let state   = o["state"] as? String ?? "-"
            let phases  = o["phases"] as? [[String: Any]] ?? []
            print("  \(offerID)  [\(state)]")
            for p in phases {
                let duration = p["regionConfig"] as? String ?? ""
                let type     = p["phaseType"] as? String ?? "-"
                print("    phase: \(type)  \(duration)")
            }
        }
    }
}

struct AndroidOffersActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "activate", abstract: "Activate an offer")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    @Option(name: .long, help: "Base plan ID")
    var basePlanID: String

    @Option(name: .long, help: "Offer ID")
    var offerID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Activating offer \(offerID) on \(productID)/\(basePlanID)")
        try await client.activateOffer(packageName: pkg, productID: productID, basePlanID: basePlanID, offerID: offerID)
        Logger.success("Offer \(offerID) activated")
    }
}
