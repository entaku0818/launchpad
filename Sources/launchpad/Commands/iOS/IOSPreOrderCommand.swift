import ArgumentParser
import Foundation

struct IOSPreOrderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preorder",
        abstract: "Manage App Store pre-orders",
        subcommands: [
            IOSPreOrderGetCommand.self,
            IOSPreOrderCreateCommand.self,
            IOSPreOrderCancelCommand.self,
        ]
    )
}

struct IOSPreOrderGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show current pre-order status")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching pre-order for \(bid)")
        let preOrder = try await client.getPreOrder(appID: appID)

        if preOrder.isEmpty {
            Logger.info("No active pre-order")
            return
        }

        guard let id = preOrder["id"] as? String,
              let attrs = preOrder["attributes"] as? [String: Any] else {
            Logger.info("No active pre-order"); return
        }

        let releaseDate  = attrs["appReleaseDate"] as? String ?? "-"
        let preOrderDate = attrs["preOrderAvailableDate"] as? String ?? "-"

        print("\nid:                    \(id)")
        print("appReleaseDate:        \(releaseDate)")
        print("preOrderAvailableDate: \(preOrderDate)")
    }
}

struct IOSPreOrderCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Enable pre-orders for an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Expected release date (YYYY-MM-DD)")
    var releaseDate: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating pre-order with release date \(releaseDate)")
        try await client.createPreOrder(appID: appID, availableDate: releaseDate)
        Logger.success("Pre-order enabled")
    }
}

struct IOSPreOrderCancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cancel", abstract: "Cancel an active pre-order")

    @Option(name: .long, help: "Pre-order ID (from preorder get)")
    var preOrderID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Cancelling pre-order \(preOrderID)")
        try await client.cancelPreOrder(preOrderID: preOrderID)
        Logger.success("Pre-order cancelled")
    }
}
