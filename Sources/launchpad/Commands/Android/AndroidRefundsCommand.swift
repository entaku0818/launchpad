import ArgumentParser
import Foundation

struct AndroidRefundsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refunds",
        abstract: "List voided (refunded/canceled) purchases"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of records to fetch (default: 20)")
    var limit: Int = 20

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching voided purchases for \(pkg)")
        let purchases = try await client.listVoidedPurchases(packageName: pkg, limit: limit)

        if purchases.isEmpty { Logger.info("No voided purchases found"); return }

        Logger.info("\(purchases.count) voided purchase(s)\n")
        for p in purchases {
            let purchaseToken = p["purchaseToken"] as? String ?? "-"
            let productID     = p["productId"] as? String ?? "-"
            let voidedTime    = p["voidedTime"] as? String ?? "-"
            let voidedReason  = voidedReasonLabel(p["voidedReason"] as? Int ?? 0)
            let kind          = p["kind"] as? String ?? "-"
            print("  \(productID)  \(voidedReason)  voided: \(voidedTime)")
            print("    token: \(purchaseToken.prefix(24))...  kind: \(kind)\n")
        }
    }

    private func voidedReasonLabel(_ reason: Int) -> String {
        switch reason {
        case 0: return "[other]"
        case 1: return "[remorse]"
        case 2: return "[not_received]"
        case 3: return "[defective]"
        case 4: return "[accidental_purchase]"
        case 5: return "[fraud]"
        case 6: return "[friendly_fraud]"
        case 7: return "[chargeback]"
        default: return "[\(reason)]"
        }
    }
}
