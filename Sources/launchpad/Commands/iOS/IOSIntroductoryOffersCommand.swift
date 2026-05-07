import ArgumentParser
import Foundation

struct IOSIntroductoryOffersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "introductory-offers",
        abstract: "Manage introductory pricing offers for new subscribers",
        subcommands: [
            IOSIntroductoryOffersListCommand.self,
            IOSIntroductoryOffersCreateCommand.self,
            IOSIntroductoryOffersDeleteCommand.self,
        ]
    )
}

struct IOSIntroductoryOffersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List introductory offers for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching introductory offers for subscription \(subscriptionID)")
        let offers = try await client.listIntroductoryOffers(subscriptionID: subscriptionID)

        if offers.isEmpty { Logger.info("No introductory offers found"); return }
        Logger.info("\(offers.count) offer(s)\n")
        for o in offers {
            guard let id = o["id"] as? String,
                  let attrs = o["attributes"] as? [String: Any] else { continue }
            let duration  = attrs["duration"] as? String ?? "-"
            let mode      = attrs["offerMode"] as? String ?? "-"
            let periods   = attrs["numberOfPeriods"] as? Int ?? 0
            let territory = (o["relationships"] as? [String: Any])?["territory"] as? [String: Any]
            let terrID    = (territory?["data"] as? [String: Any])?["id"] as? String ?? "-"
            print("  [\(terrID)] mode: \(mode)  duration: \(duration) x\(periods)  id: \(id)")
        }
    }
}

struct IOSIntroductoryOffersCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an introductory offer for a territory")

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Duration in ISO 8601 (e.g. P1W, P1M, P3M)")
    var duration: String

    @Option(name: .long, help: "Offer mode: FREE_TRIAL, PAY_AS_YOU_GO, or PAY_UP_FRONT")
    var offerMode: String = "FREE_TRIAL"

    @Option(name: .long, help: "Number of periods (e.g. 1 for 1 month)")
    var numberOfPeriods: Int = 1

    @Option(name: .long, help: "Territory code (e.g. USA, JPN)")
    var territory: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating introductory offer (\(offerMode) \(duration) x\(numberOfPeriods)) for \(territory)")
        let id = try await client.createIntroductoryOffer(
            subscriptionID: subscriptionID,
            duration: duration,
            offerMode: offerMode,
            numberOfPeriods: numberOfPeriods,
            territory: territory
        )
        Logger.success("Introductory offer created: \(id)")
    }
}

struct IOSIntroductoryOffersDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an introductory offer")

    @Option(name: .long, help: "Introductory offer ID (from list)")
    var offerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting introductory offer \(offerID)")
        try await client.deleteIntroductoryOffer(offerID: offerID)
        Logger.success("Introductory offer deleted")
    }
}
