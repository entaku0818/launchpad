import ArgumentParser
import Foundation

struct IOSIAPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Manage App Store in-app purchases",
        subcommands: [
            IOSIAPListCommand.self,
            IOSIAPGetCommand.self,
            IOSIAPCreateCommand.self,
            IOSIAPUpdateCommand.self,
            IOSIAPDeleteCommand.self,
        ]
    )
}

struct IOSIAPListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List in-app purchases for an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching in-app purchases for \(bid)")
        let iaps = try await client.listInAppPurchases(appID: appID)

        if iaps.isEmpty { Logger.info("No in-app purchases found"); return }
        Logger.info("\(iaps.count) IAP(s)\n")
        for i in iaps {
            guard let id = i["id"] as? String,
                  let attrs = i["attributes"] as? [String: Any] else { continue }
            let name      = attrs["name"] as? String ?? attrs["referenceName"] as? String ?? "-"
            let productID = attrs["productID"] as? String ?? attrs["productId"] as? String ?? "-"
            let iapType   = attrs["inAppPurchaseType"] as? String ?? "-"
            let state     = attrs["state"] as? String ?? "-"
            print("  \(productID)  [\(iapType)]  state: \(state)")
            print("    name: \(name)  id: \(id)\n")
        }
    }
}

struct IOSIAPGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show details of an in-app purchase")

    @Option(name: .long, help: "In-app purchase ID")
    var iapID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching IAP \(iapID)")
        let iap = try await client.getInAppPurchase(iapID: iapID)

        guard let attrs = iap["attributes"] as? [String: Any] else {
            Logger.error("IAP not found"); Foundation.exit(1)
        }
        let name      = attrs["name"] as? String ?? attrs["referenceName"] as? String ?? "-"
        let productID = attrs["productId"] as? String ?? "-"
        let iapType   = attrs["inAppPurchaseType"] as? String ?? "-"
        let state     = attrs["state"] as? String ?? "-"

        print("\nid:        \(iapID)")
        print("productId: \(productID)")
        print("name:      \(name)")
        print("type:      \(iapType)")
        print("state:     \(state)")
    }
}

struct IOSIAPCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new in-app purchase")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Product ID (e.g. com.example.premium)")
    var productID: String

    @Option(name: .long, help: "Reference name (internal)")
    var name: String

    @Option(name: .long, help: "Type: CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION")
    var iapType: String = "NON_CONSUMABLE"

    @Option(name: .long, help: "Optional review note for App Review")
    var reviewNote: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating IAP '\(productID)' [\(iapType)]")
        let id = try await client.createInAppPurchase(appID: appID, productID: productID, name: name, iapType: iapType, reviewNote: reviewNote)
        Logger.success("IAP created: \(id)")
    }
}

struct IOSIAPUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update an in-app purchase reference name or review note")

    @Option(name: .long, help: "In-app purchase ID")
    var iapID: String

    @Option(name: .long, help: "New reference name")
    var name: String?

    @Option(name: .long, help: "New review note for App Review")
    var reviewNote: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating IAP \(iapID)")
        try await client.updateInAppPurchase(iapID: iapID, name: name, reviewNote: reviewNote)
        Logger.success("IAP updated")
    }
}

struct IOSIAPDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an in-app purchase")

    @Option(name: .long, help: "In-app purchase ID")
    var iapID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting IAP \(iapID)")
        try await client.deleteInAppPurchase(iapID: iapID)
        Logger.success("IAP deleted")
    }
}
