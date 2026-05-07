import ArgumentParser
import Foundation

struct AndroidOrdersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "orders",
        abstract: "Manage Play Store orders",
        subcommands: [
            AndroidOrdersGetCommand.self,
            AndroidOrdersRefundCommand.self,
        ]
    )
}

struct AndroidOrdersGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get details for a specific order")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Order ID (e.g. GPA.1234-5678-9012-34567)")
    var orderID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching order \(orderID)")
        let order = try await client.getOrder(packageName: pkg, orderID: orderID)

        let kind      = order["kind"] as? String ?? "-"
        let startTime = order["creationTime"] as? String ?? "-"
        print("Order ID:  \(orderID)")
        print("Kind:      \(kind)")
        print("Created:   \(startTime)")
        if let lines = order["lineItems"] as? [[String: Any]] {
            for (i, line) in lines.enumerated() {
                let productID = line["productId"] as? String ?? "-"
                let amount    = (line["priceMicros"] as? String).map { "\($0) micros" } ?? "-"
                print("Item[\(i)]: \(productID)  \(amount)")
            }
        }
    }
}

struct AndroidOrdersRefundCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "refund", abstract: "Refund an order (optionally revoke entitlement)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Order ID (e.g. GPA.1234-5678-9012-34567)")
    var orderID: String

    @Flag(name: .long, help: "Revoke the entitlement in addition to refunding")
    var revoke: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Refunding order \(orderID)\(revoke ? " (revoking entitlement)" : "")")
        try await client.refundOrder(packageName: pkg, orderID: orderID, revoke: revoke)
        Logger.success("Order \(orderID) refunded")
    }
}
