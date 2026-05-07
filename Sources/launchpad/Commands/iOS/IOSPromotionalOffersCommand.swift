import ArgumentParser
import Foundation

struct IOSPromotionalOffersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "promotional-offers",
        abstract: "Manage subscription promotional offers for existing/lapsed subscribers",
        subcommands: [
            IOSPromotionalOffersListCommand.self,
            IOSPromotionalOffersCreateCommand.self,
            IOSPromotionalOffersDeleteCommand.self,
        ]
    )
}

struct IOSPromotionalOffersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List promotional offers for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching promotional offers for subscription \(subscriptionID)")
        let offers = try await client.listPromotionalOffers(subscriptionID: subscriptionID)

        if offers.isEmpty { Logger.info("No promotional offers found"); return }
        Logger.info("\(offers.count) offer(s)\n")
        for o in offers {
            guard let id = o["id"] as? String,
                  let attrs = o["attributes"] as? [String: Any] else { continue }
            let offerID = attrs["offerId"] as? String ?? "-"
            let name    = attrs["name"] as? String ?? "-"
            print("  \(offerID)  \(name)  id: \(id)")
        }
    }
}

struct IOSPromotionalOffersCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a promotional offer for a subscription")

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Offer identifier (unique string)")
    var offerID: String

    @Option(name: .long, help: "Display name for the offer")
    var name: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating promotional offer '\(offerID)'")
        let id = try await client.createPromotionalOffer(subscriptionID: subscriptionID, offerID: offerID, name: name)
        Logger.success("Promotional offer created: \(id)")
    }
}

struct IOSPromotionalOffersDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a promotional offer")

    @Option(name: .long, help: "Promotional offer ID (from list)")
    var offerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting promotional offer \(offerID)")
        try await client.deletePromotionalOffer(offerID: offerID)
        Logger.success("Promotional offer deleted")
    }
}
