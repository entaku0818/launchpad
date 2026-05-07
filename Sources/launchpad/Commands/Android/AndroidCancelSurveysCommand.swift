import ArgumentParser
import Foundation

struct AndroidCancelSurveysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel-surveys",
        abstract: "View subscription cancellation survey responses",
        subcommands: [
            AndroidCancelSurveysGetCommand.self,
        ]
    )
}

struct AndroidCancelSurveysGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get cancellation survey data for a subscription token")

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
        Logger.step("Fetching subscription details for token")
        let result = try await client.getCancelSurvey(packageName: pkg, subscriptionID: subscriptionID, token: token)

        let lineItems = result["lineItems"] as? [[String: Any]] ?? []
        let startTime = result["startTime"] as? String ?? "-"
        let testPurchase = result["testPurchase"] as? [String: Any]

        print("\nstartTime:    \(startTime)")
        if testPurchase != nil { print("testPurchase: YES") }

        for item in lineItems {
            let productID      = item["productId"] as? String ?? "-"
            let expiryTime     = item["expiryTime"] as? String ?? "-"
            let autoRenewing   = (item["autoRenewingPlan"] as? [String: Any])?["autoRenewEnabled"] as? Bool ?? false
            let cancelSurvey   = (item["cancelSurveyResult"] as? [String: Any])
            let cancelReason   = cancelSurvey?["reason"] as? String ?? "-"
            let cancelFeedback = cancelSurvey?["reasonUserInput"] as? String

            print("\nproduct:      \(productID)")
            print("expiryTime:   \(expiryTime)")
            print("autoRenewing: \(autoRenewing)")
            if cancelSurvey != nil {
                print("cancelReason: \(cancelReason)")
                if let fb = cancelFeedback { print("feedback:     \(fb)") }
            }
        }
    }
}
