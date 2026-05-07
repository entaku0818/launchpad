import ArgumentParser
import Foundation

struct AndroidSubscriptionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Manage Google Play subscriptions",
        subcommands: [
            AndroidSubscriptionsListCommand.self,
            AndroidSubscriptionsGetCommand.self,
            AndroidSubscriptionsActivateCommand.self,
            AndroidSubscriptionsDeactivateCommand.self,
            AndroidBasePlansListCommand.self,
            AndroidSubscriptionsCreateCommand.self,
            AndroidSubscriptionsDeleteCommand.self,
        ]
    )
}

// MARK: - list

struct AndroidSubscriptionsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all subscriptions"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching subscriptions for \(pkg)")
        let subs = try await client.listSubscriptions(packageName: pkg)

        if subs.isEmpty { Logger.info("No subscriptions found"); return }

        Logger.info("\(subs.count) subscription(s)\n")
        for sub in subs {
            let productID = sub["productId"] as? String ?? "-"
            let listings = sub["listings"] as? [[String: Any]]
            let title = listings?.first?["title"] as? String ?? ""
            let basePlans = sub["basePlans"] as? [[String: Any]] ?? []
            print("  \(productID)  \(title)")
            for bp in basePlans {
                let bpID = bp["basePlanId"] as? String ?? "-"
                let state = bp["state"] as? String ?? "-"
                print("    basePlan: \(bpID)  [\(state)]")
            }
        }
    }
}

// MARK: - get

struct AndroidSubscriptionsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show details of a subscription"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching \(productID)")
        let sub = try await client.getSubscription(packageName: pkg, productID: productID)

        let listings = sub["listings"] as? [[String: Any]] ?? []
        let basePlans = sub["basePlans"] as? [[String: Any]] ?? []

        print("\nproductId: \(productID)")

        if !listings.isEmpty {
            print("listings:")
            for l in listings {
                let lang  = l["languageCode"] as? String ?? "-"
                let title = l["title"] as? String ?? ""
                let desc  = l["description"] as? String ?? ""
                print("  [\(lang)] \(title)")
                if !desc.isEmpty { print("    \(desc)") }
            }
        }

        if !basePlans.isEmpty {
            print("basePlans:")
            for bp in basePlans {
                let bpID  = bp["basePlanId"] as? String ?? "-"
                let state = bp["state"] as? String ?? "-"
                print("  \(bpID)  [\(state)]")
            }
        }
    }
}

// MARK: - activate

struct AndroidSubscriptionsActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Activate a subscription base plan"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    @Option(name: .long, help: "Base plan ID")
    var basePlanID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Activating \(productID)/\(basePlanID)")
        try await client.activateBasePlan(packageName: pkg, productID: productID, basePlanID: basePlanID)
        Logger.success("Base plan \(basePlanID) activated")
    }
}

// MARK: - deactivate

struct AndroidSubscriptionsDeactivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deactivate",
        abstract: "Deactivate a subscription base plan"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    @Option(name: .long, help: "Base plan ID")
    var basePlanID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Deactivating \(productID)/\(basePlanID)")
        try await client.deactivateBasePlan(packageName: pkg, productID: productID, basePlanID: basePlanID)
        Logger.success("Base plan \(basePlanID) deactivated")
    }
}

struct AndroidBasePlansListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "base-plans", abstract: "List base plans for a subscription")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Subscription product ID")
    var productID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching base plans for \(productID)")
        let plans = try await client.listBasePlans(packageName: pkg, productID: productID)

        if plans.isEmpty { Logger.info("No base plans found"); return }
        Logger.info("\(plans.count) base plan(s)\n")
        for p in plans {
            let id     = p["basePlanId"] as? String ?? "-"
            let state  = p["state"] as? String ?? "-"
            let autoRenewingPlan = p["autoRenewingBasePlanType"] as? [String: Any]
            let period = autoRenewingPlan?["billingPeriodDuration"] as? String ?? "-"
            print("  \(id)  state: \(state)  period: \(period)")
        }
    }
}

struct AndroidSubscriptionsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new subscription product")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product ID (SKU)")
    var productID: String

    @Option(name: .long, help: "Title (English)")
    var title: String

    @Option(name: .long, help: "Benefits description (English)")
    var benefits: String = ""

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Creating subscription '\(productID)'")
        try await client.createSubscription(
            packageName: pkg,
            productID: productID,
            referenceName: title,
            listings: ["en-US": ["title": title, "benefits": benefits]]
        )
        Logger.success("Subscription '\(productID)' created")
    }
}

struct AndroidSubscriptionsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription product")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product ID (SKU)")
    var productID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deleting subscription '\(productID)'")
        try await client.deleteSubscription(packageName: pkg, productID: productID)
        Logger.success("Subscription '\(productID)' deleted")
    }
}
