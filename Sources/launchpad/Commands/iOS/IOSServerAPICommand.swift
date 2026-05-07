import ArgumentParser
import Foundation

struct IOSServerAPICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server-api",
        abstract: "App Store Server API: verify transactions, subscription status, refunds, and notifications",
        subcommands: [
            IOSServerAPIHistoryCommand.self,
            IOSServerAPISubscriptionCommand.self,
            IOSServerAPIRefundsCommand.self,
            IOSServerAPITestNotificationCommand.self,
            IOSServerAPINotificationHistoryCommand.self,
            IOSServerAPIExtendCommand.self,
        ]
    )
}

// MARK: - helpers

private func makeClient(sandbox: Bool) throws -> AppStoreServerClient {
    return AppStoreServerClient(credentials: try ASCCredentials.fromEnvironment(), sandbox: sandbox)
}

private func formatTimestamp(_ ms: Any?) -> String {
    guard let ms = ms as? Int64 ?? (ms as? Int).map(Int64.init) else { return "-" }
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    let f = ISO8601DateFormatter()
    return f.string(from: date)
}

// MARK: - transaction history

struct IOSServerAPIHistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "history", abstract: "Get transaction history for an original transaction ID")

    @Option(name: .long, help: "Original transaction ID")
    var originalTransactionID: String

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    @Option(name: .long, help: "Max transactions to show (default: 20)")
    var limit: Int = 20

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(sandbox: sandbox)
        Logger.step("Fetching transaction history for \(originalTransactionID)\(sandbox ? " [SANDBOX]" : "")")
        let txns = try await client.getAllTransactions(originalTransactionID: originalTransactionID)

        if txns.isEmpty { Logger.info("No transactions found"); return }
        Logger.info("\(txns.count) transaction(s)\n")
        for t in txns.prefix(limit) {
            let productID   = t["productId"] as? String ?? "-"
            let type        = t["type"] as? String ?? "-"
            let txID        = t["transactionId"] as? String ?? "-"
            let purchaseDate = formatTimestamp(t["purchaseDate"])
            let expiresDate  = formatTimestamp(t["expiresDate"])
            let revoked      = t["revocationDate"] != nil ? "  REVOKED" : ""
            print("  \(productID)  [\(type)]\(revoked)")
            print("    txID: \(txID)")
            print("    purchased: \(purchaseDate)")
            if t["expiresDate"] != nil { print("    expires:   \(expiresDate)") }
            print("")
        }
        if txns.count > limit { Logger.info("(showing \(limit) of \(txns.count))") }
    }
}

// MARK: - subscription status

struct IOSServerAPISubscriptionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "subscription", abstract: "Get current subscription status for an original transaction ID")

    @Option(name: .long, help: "Original transaction ID")
    var originalTransactionID: String

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(sandbox: sandbox)
        Logger.step("Fetching subscription status for \(originalTransactionID)\(sandbox ? " [SANDBOX]" : "")")
        let result = try await client.getSubscriptionStatuses(originalTransactionID: originalTransactionID)

        let data = result["data"] as? [[String: Any]] ?? []
        if data.isEmpty { Logger.info("No subscription data found"); return }

        for group in data {
            let groupID         = group["subscriptionGroupIdentifier"] as? String ?? "-"
            let lastTransactions = group["lastTransactions"] as? [[String: Any]] ?? []
            print("Subscription group: \(groupID)")
            for txn in lastTransactions {
                let status      = txn["status"] as? Int ?? -1
                let productID   = (client.decodeJWTPayload(txn["signedTransactionInfo"] as? String ?? ""))["productId"] as? String ?? "-"
                let renewal     = client.decodeJWTPayload(txn["signedRenewalInfo"] as? String ?? "")
                let autoRenew   = renewal["autoRenewStatus"] as? Int == 1
                let statusLabel: String
                switch status {
                case 1: statusLabel = "Active"
                case 2: statusLabel = "Expired"
                case 3: statusLabel = "In Billing Retry"
                case 4: statusLabel = "In Grace Period"
                case 5: statusLabel = "Revoked"
                default: statusLabel = "Unknown(\(status))"
                }
                print("  \(productID)  [\(statusLabel)]  autoRenew: \(autoRenew)")
            }
            print("")
        }
    }
}

// MARK: - refund lookup

struct IOSServerAPIRefundsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "refunds", abstract: "Look up refunded transactions for an original transaction ID")

    @Option(name: .long, help: "Original transaction ID")
    var originalTransactionID: String

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(sandbox: sandbox)
        Logger.step("Fetching refund history for \(originalTransactionID)\(sandbox ? " [SANDBOX]" : "")")
        let refunds = try await client.getRefundHistory(originalTransactionID: originalTransactionID)

        if refunds.isEmpty { Logger.info("No refunds found"); return }
        Logger.info("\(refunds.count) refunded transaction(s)\n")
        for r in refunds {
            let productID      = r["productId"] as? String ?? "-"
            let txID           = r["transactionId"] as? String ?? "-"
            let revocationDate = formatTimestamp(r["revocationDate"])
            let reason         = r["revocationReason"] as? Int
            let reasonLabel    = reason == 0 ? "other" : reason == 1 ? "issue" : "-"
            print("  \(productID)  txID: \(txID)  refunded: \(revocationDate)  reason: \(reasonLabel)")
        }
    }
}

// MARK: - test notification

struct IOSServerAPITestNotificationCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "test-notification", abstract: "Send a test App Store server notification to your endpoint")

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    @Option(name: .long, help: "If provided, check the status of an existing test token instead of creating a new one")
    var token: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(sandbox: sandbox)

        if let existingToken = token {
            Logger.step("Checking test notification status for token")
            let status = try await client.getTestNotificationStatus(testToken: existingToken)
            let deliveries = status["deliveryStatus"] as? Int ?? -1
            let attempts   = status["sendAttempts"] as? [[String: Any]] ?? []
            print("deliveryStatus: \(deliveries)")
            for a in attempts {
                let ts     = formatTimestamp(a["attemptDate"])
                let result = a["sendAttemptResult"] as? String ?? "-"
                print("  attempt: \(ts)  result: \(result)")
            }
        } else {
            Logger.step("Sending test server notification\(sandbox ? " [SANDBOX]" : "")")
            let testToken = try await client.sendTestNotification()
            Logger.success("Test notification sent")
            Logger.info("Token: \(testToken)")
            Logger.info("Check delivery with:  launchpad ios server-api test-notification --token \(testToken)")
        }
    }
}

// MARK: - notification history

struct IOSServerAPINotificationHistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "notification-history", abstract: "Retrieve past App Store server notification events")

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    @Option(name: .long, help: "Start date in milliseconds since epoch")
    var startDate: String

    @Option(name: .long, help: "End date in milliseconds since epoch")
    var endDate: String

    @Option(name: .long, help: "Filter by notification type (e.g. SUBSCRIBED, DID_RENEW, EXPIRED)")
    var type: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(sandbox: sandbox)
        Logger.step("Fetching notification history\(sandbox ? " [SANDBOX]" : "")")
        let history = try await client.getNotificationHistory(startDate: startDate, endDate: endDate, notificationType: type)

        if history.isEmpty { Logger.info("No notifications found in range"); return }
        Logger.info("\(history.count) notification(s)\n")
        for n in history {
            let status   = n["sendAttemptResult"] as? String ?? "-"
            let payload  = client.decodeJWTPayload(n["signedPayload"] as? String ?? "")
            let notifType = (payload["data"] as? [String: Any])?["type"] as? String ?? payload["notificationType"] as? String ?? "-"
            let subtype   = (payload["data"] as? [String: Any])?["subtype"] as? String ?? ""
            print("  [\(notifType)\(subtype.isEmpty ? "" : "/\(subtype)")] result: \(status)")
        }
    }
}

// MARK: - extend subscription

struct IOSServerAPIExtendCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "extend", abstract: "Extend a subscription's renewal date (e.g. for service outages)")

    @Option(name: .long, help: "Original transaction ID")
    var originalTransactionID: String

    @Option(name: .long, help: "Product ID of the subscription")
    var productID: String

    @Option(name: .long, help: "Number of days to extend (1–90)")
    var days: Int

    @Option(name: .long, help: "Reason code: 0=undeclared, 1=internal issue, 2=outage, 3=other (default: 0)")
    var reason: Int = 0

    @Flag(name: .long, help: "Use sandbox environment")
    var sandbox: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        guard days >= 1 && days <= 90 else {
            Logger.error("--days must be between 1 and 90"); Foundation.exit(1)
        }
        let client = try makeClient(sandbox: sandbox)
        Logger.step("Extending subscription \(originalTransactionID) by \(days) day(s)")
        _ = try await client.extendSubscriptionRenewalDate(
            originalTransactionID: originalTransactionID,
            productID: productID,
            extendByDays: days,
            reason: reason
        )
        Logger.success("Subscription extended by \(days) day(s)")
    }
}
