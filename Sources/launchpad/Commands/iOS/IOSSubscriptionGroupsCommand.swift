import ArgumentParser
import Foundation

struct IOSSubscriptionGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-groups",
        abstract: "Manage in-app subscription groups and their products",
        subcommands: [
            IOSSubscriptionGroupsListCommand.self,
            IOSSubscriptionGroupsProductsCommand.self,
            IOSSubscriptionGroupsCreateCommand.self,
            IOSSubscriptionGroupsDeleteCommand.self,
        ]
    )
}

struct IOSSubscriptionGroupsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List subscription groups")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching subscription groups for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let groups = try await client.getSubscriptionGroups(appID: appID)

        if groups.isEmpty { Logger.info("No subscription groups found"); return }
        Logger.info("\(groups.count) group(s)\n")
        for g in groups {
            guard let id = g["id"] as? String,
                  let attrs = g["attributes"] as? [String: Any] else { continue }
            let name = attrs["referenceName"] as? String ?? "-"
            print("  \(name)  id: \(id)")
        }
    }
}

struct IOSSubscriptionGroupsProductsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "products", abstract: "List subscriptions in a group")

    @Option(name: .long, help: "Subscription group ID")
    var groupID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching subscriptions in group \(groupID)")
        let subs = try await client.getSubscriptions(groupID: groupID)

        if subs.isEmpty { Logger.info("No subscriptions in this group"); return }
        Logger.info("\(subs.count) subscription(s)\n")
        for s in subs {
            guard let attrs = s["attributes"] as? [String: Any] else { continue }
            let productID = attrs["productID"] as? String ?? "-"
            let name      = attrs["name"] as? String ?? "-"
            let state     = attrs["state"] as? String ?? "-"
            let period    = attrs["subscriptionPeriod"] as? String ?? "-"
            print("  \(productID)  \(name)  [\(state)]  period: \(period)")
        }
    }
}

struct IOSSubscriptionGroupsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new subscription group")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Internal reference name for the group")
    var referenceName: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating subscription group '\(referenceName)'")
        let id = try await client.createSubscriptionGroup(appID: appID, referenceName: referenceName)
        Logger.success("Subscription group created: \(id)")
    }
}

struct IOSSubscriptionGroupsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription group")

    @Option(name: .long, help: "Subscription group ID (from list)")
    var groupID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting subscription group \(groupID)")
        try await client.deleteSubscriptionGroup(groupID: groupID)
        Logger.success("Subscription group deleted")
    }
}
