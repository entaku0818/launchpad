import ArgumentParser
import Foundation

struct IOSSubscriptionAvailabilityCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-availability",
        abstract: "Manage territory availability for a subscription",
        subcommands: [
            IOSSubAvailGetCommand.self,
            IOSSubAvailSetCommand.self,
        ]
    )
}

struct IOSSubAvailGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show territory availability for a subscription")

    @Option(name: .long, help: "Subscription ID (from ios subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching availability for subscription \(subscriptionID)")
        let availability = try await client.getSubscriptionAvailability(subscriptionID: subscriptionID)

        guard let id = availability["id"] as? String,
              let attrs = availability["attributes"] as? [String: Any] else {
            Logger.info("No availability data found"); return
        }
        let newTerritories = attrs["availableInNewTerritories"] as? Bool ?? false
        print("ID:                          \(id)")
        print("availableInNewTerritories:   \(newTerritories)")

        if let included = availability["relationships"] as? [String: Any],
           let avail = included["availableTerritories"] as? [String: Any],
           let data = avail["data"] as? [[String: Any]] {
            let codes = data.compactMap { $0["id"] as? String }.sorted()
            print("Territories (\(codes.count)):        \(codes.joined(separator: ", "))")
        }
    }
}

struct IOSSubAvailSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set territory availability for a subscription")

    @Option(name: .long, help: "Subscription ID (from ios subscription-groups products)")
    var subscriptionID: String

    @Option(name: .long, help: "Comma-separated territory codes (e.g. USA,JPN,GBR)")
    var territories: String

    @Flag(name: .long, help: "Make available in new territories automatically")
    var availableInNewTerritories: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let codes = territories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Setting availability for subscription \(subscriptionID): \(codes.count) territory/territories")
        let id = try await client.createSubscriptionAvailability(
            subscriptionID: subscriptionID,
            availableInNewTerritories: availableInNewTerritories,
            territoryCodes: codes
        )
        Logger.success("Subscription availability updated: \(id)")
    }
}
