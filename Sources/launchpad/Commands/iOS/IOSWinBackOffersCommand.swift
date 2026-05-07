import ArgumentParser
import Foundation

struct IOSWinBackOffersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "win-back-offers",
        abstract: "Manage win-back offers for auto-renewable subscriptions",
        subcommands: [
            IOSWinBackOffersListCommand.self,
            IOSWinBackOffersCreateCommand.self,
            IOSWinBackOffersDeleteCommand.self,
        ]
    )
}

struct IOSWinBackOffersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List win-back offers for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching win-back offers for subscription \(subscriptionID)")
        let offers = try await client.listWinBackOffers(subscriptionID: subscriptionID)

        if offers.isEmpty { Logger.info("No win-back offers found"); return }
        Logger.info("\(offers.count) offer(s)\n")
        for o in offers {
            guard let id = o["id"] as? String,
                  let attrs = o["attributes"] as? [String: Any] else { continue }
            let offerID  = attrs["offerId"] as? String ?? "-"
            let priority = attrs["priority"] as? String ?? "-"
            let mode     = attrs["offerMode"] as? String ?? "-"
            let duration = attrs["duration"] as? String ?? "-"
            print("  \(offerID)  mode: \(mode)  duration: \(duration)  priority: \(priority)  id: \(id)")
        }
    }
}

struct IOSWinBackOffersCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a win-back offer")

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Offer identifier (unique string)")
    var offerID: String

    @Option(name: .long, help: "Priority: HIGH or NORMAL (default: NORMAL)")
    var priority: String = "NORMAL"

    @Option(name: .long, help: "Minimum paid months before lapse (default: 1)")
    var paidMonths: Int = 1

    @Option(name: .long, help: "Minimum months since lapse (default: 2)")
    var lapseMonths: Int = 2

    @Option(name: .long, help: "Offer mode: FREE_TRIAL, PAY_AS_YOU_GO, or PAY_UP_FRONT (default: FREE_TRIAL)")
    var offerMode: String = "FREE_TRIAL"

    @Option(name: .long, help: "Offer duration in ISO 8601 (e.g. P1M)")
    var duration: String = "P1M"

    @Option(name: .long, help: "Eligibility: ALL_PRODUCTS_LAPSED or SPECIFIC_PRODUCT_LAPSED (default: ALL_PRODUCTS_LAPSED)")
    var eligibility: String = "ALL_PRODUCTS_LAPSED"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating win-back offer '\(offerID)'")
        let id = try await client.createWinBackOffer(
            subscriptionID: subscriptionID,
            offerId: offerID,
            priority: priority,
            customerEligibilityPaidSubscriptionDurationInMonths: paidMonths,
            customerEligibilityTimeSinceLastSubscribedInMonths: lapseMonths,
            offerMode: offerMode,
            duration: duration,
            offerEligibility: eligibility
        )
        Logger.success("Win-back offer created: \(id)")
    }
}

struct IOSWinBackOffersDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a win-back offer")

    @Option(name: .long, help: "Win-back offer ID (from list)")
    var offerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting win-back offer \(offerID)")
        try await client.deleteWinBackOffer(offerID: offerID)
        Logger.success("Win-back offer deleted")
    }
}
