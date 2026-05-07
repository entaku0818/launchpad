import ArgumentParser
import Foundation

struct AndroidPurchasesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "purchases",
        abstract: "Verify and acknowledge in-app purchases and subscriptions",
        subcommands: [
            AndroidPurchasesVerifyProductCommand.self,
            AndroidPurchasesVerifySubscriptionCommand.self,
            AndroidPurchasesAcknowledgeProductCommand.self,
            AndroidPurchasesAcknowledgeSubscriptionCommand.self,
            AndroidPurchasesConsumeCommand.self,
            AndroidPurchasesDeferCommand.self,
        ]
    )
}

struct AndroidPurchasesVerifyProductCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "verify-product", abstract: "Verify a one-time product purchase")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product ID (SKU)")
    var productID: String

    @Option(name: .long, help: "Purchase token from the client")
    var token: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Verifying product purchase: \(productID)")
        let result = try await client.verifyProductPurchase(packageName: pkg, productID: productID, token: token)

        let purchaseState    = result["purchaseState"] as? Int ?? -1
        let consumptionState = result["consumptionState"] as? Int ?? -1
        let orderId          = result["orderId"] as? String ?? "-"
        let purchaseTime     = result["purchaseTimeMillis"] as? String ?? "-"
        let acknowledged     = result["acknowledgementState"] as? Int ?? -1

        let stateLabel = purchaseState == 0 ? "PURCHASED" : purchaseState == 1 ? "CANCELLED" : purchaseState == 2 ? "PENDING" : "UNKNOWN(\(purchaseState))"
        let consumedLabel = consumptionState == 0 ? "NOT_CONSUMED" : "CONSUMED"
        let ackLabel = acknowledged == 0 ? "NOT_ACKNOWLEDGED" : "ACKNOWLEDGED"

        print("\npurchaseState:      \(stateLabel)")
        print("consumptionState:   \(consumedLabel)")
        print("acknowledgement:    \(ackLabel)")
        print("orderId:            \(orderId)")
        print("purchaseTimeMillis: \(purchaseTime)")
    }
}

struct AndroidPurchasesVerifySubscriptionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "verify-subscription", abstract: "Verify a subscription purchase")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Purchase token from the client")
    var token: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Verifying subscription: \(subscriptionID)")
        let result = try await client.verifySubscriptionPurchase(packageName: pkg, subscriptionID: subscriptionID, token: token)

        let expiryTime  = result["expiryTimeMillis"] as? String ?? "-"
        let startTime   = result["startTimeMillis"] as? String ?? "-"
        let autoRenew   = result["autoRenewing"] as? Bool ?? false
        let cancelReason = result["cancelReason"] as? Int
        let paymentState = result["paymentState"] as? Int ?? -1
        let acknowledged = result["acknowledgementState"] as? Int ?? -1

        let paymentLabel = paymentState == 0 ? "PENDING" : paymentState == 1 ? "RECEIVED" : paymentState == 2 ? "FREE_TRIAL" : "UNKNOWN(\(paymentState))"
        let ackLabel = acknowledged == 0 ? "NOT_ACKNOWLEDGED" : "ACKNOWLEDGED"

        print("\nstartTime:        \(startTime)")
        print("expiryTime:       \(expiryTime)")
        print("autoRenewing:     \(autoRenew)")
        print("paymentState:     \(paymentLabel)")
        print("acknowledgement:  \(ackLabel)")
        if let cr = cancelReason {
            let crLabel = cr == 0 ? "USER_CANCELLED" : cr == 1 ? "SYSTEM_CANCELLED" : cr == 2 ? "REPLACED" : cr == 3 ? "DEVELOPER_CANCELLED" : "UNKNOWN"
            print("cancelReason:     \(crLabel)")
        }
    }
}

struct AndroidPurchasesAcknowledgeProductCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "acknowledge-product", abstract: "Acknowledge a one-time product purchase")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product ID (SKU)")
    var productID: String

    @Option(name: .long, help: "Purchase token")
    var token: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Acknowledging product purchase: \(productID)")
        try await client.acknowledgePurchase(packageName: pkg, productID: productID, token: token)
        Logger.success("Purchase acknowledged")
    }
}

struct AndroidPurchasesAcknowledgeSubscriptionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "acknowledge-subscription", abstract: "Acknowledge a subscription purchase")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription ID")
    var subscriptionID: String

    @Option(name: .long, help: "Purchase token")
    var token: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Acknowledging subscription: \(subscriptionID)")
        try await client.acknowledgeSubscription(packageName: pkg, subscriptionID: subscriptionID, token: token)
        Logger.success("Subscription acknowledged")
    }
}

struct AndroidPurchasesConsumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "consume", abstract: "Consume a one-time purchase (marks as consumed so it can be repurchased)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product ID (SKU)")
    var productID: String

    @Option(name: .long, help: "Purchase token")
    var token: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Consuming purchase of \(productID)")
        try await client.consumePurchase(packageName: pkg, productID: productID, token: token)
        Logger.success("Purchase consumed")
    }
}

struct AndroidPurchasesDeferCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "defer", abstract: "Defer a subscription renewal to a future date")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var subscriptionID: String

    @Option(name: .long, help: "Purchase token")
    var token: String

    @Option(name: .long, help: "Desired expiry time in Unix milliseconds")
    var expiryTimeMillis: Int64

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deferring subscription \(subscriptionID) to \(expiryTimeMillis)ms")
        let newExpiry = try await client.deferSubscription(packageName: pkg, subscriptionID: subscriptionID, token: token, desiredExpiryTimeMillis: expiryTimeMillis)
        Logger.success("Subscription deferred. New expiry: \(newExpiry) ms")
    }
}
