import ArgumentParser
import Foundation

struct AndroidOffersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "offers",
        abstract: "Manage subscription base plan offers (free trials, intro pricing)",
        subcommands: [
            AndroidOffersListCommand.self,
            AndroidOffersActivateCommand.self,
            AndroidOffersCreateCommand.self,
            AndroidOffersDeactivateCommand.self,
            AndroidOffersDeleteCommand.self,
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

struct AndroidOffersCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a free trial offer for a base plan")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    @Option(name: .long, help: "Base plan ID")
    var basePlanID: String

    @Option(name: .long, help: "Offer ID (unique identifier)")
    var offerID: String

    @Option(name: .long, help: "Free trial duration in ISO 8601 format (e.g. P7D for 7 days)")
    var trialDuration: String = "P7D"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let phases: [[String: Any]] = [
            [
                "recurrenceCount": 1,
                "duration": trialDuration,
                "regionalConfigs": [],
            ]
        ]

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Creating free trial offer '\(offerID)' (\(trialDuration)) for \(productID)/\(basePlanID)")
        try await client.createSubscriptionOffer(packageName: pkg, productID: productID, basePlanID: basePlanID, offerID: offerID, phases: phases)
        Logger.success("Offer '\(offerID)' created")
    }
}

struct AndroidOffersDeactivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "deactivate", abstract: "Deactivate an offer")

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
        Logger.step("Deactivating offer \(offerID) on \(productID)/\(basePlanID)")
        try await client.deactivateOffer(packageName: pkg, productID: productID, basePlanID: basePlanID, offerID: offerID)
        Logger.success("Offer \(offerID) deactivated")
    }
}

struct AndroidOffersDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an offer")

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
        Logger.step("Deleting offer \(offerID) from \(productID)/\(basePlanID)")
        try await client.deleteOffer(packageName: pkg, productID: productID, basePlanID: basePlanID, offerID: offerID)
        Logger.success("Offer \(offerID) deleted")
    }
}
