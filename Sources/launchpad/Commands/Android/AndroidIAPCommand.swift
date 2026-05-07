import ArgumentParser
import Foundation

struct AndroidIAPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Manage Google Play in-app products (one-time purchases)",
        subcommands: [
            AndroidIAPListCommand.self,
            AndroidIAPGetCommand.self,
            AndroidIAPActivateCommand.self,
            AndroidIAPDeactivateCommand.self,
            AndroidIAPCreateCommand.self,
            AndroidIAPDeleteCommand.self,
        ]
    )
}

// MARK: - list

struct AndroidIAPListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all in-app products"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching in-app products for \(pkg)")
        let products = try await client.listIAP(packageName: pkg)

        if products.isEmpty { Logger.info("No in-app products found"); return }

        Logger.info("\(products.count) product(s)\n")
        for p in products {
            let sku    = p["sku"] as? String ?? "-"
            let status = p["status"] as? String ?? "-"
            let price  = (p["defaultPrice"] as? [String: Any])?["priceMicros"] as? String ?? "-"
            let currency = (p["defaultPrice"] as? [String: Any])?["currency"] as? String ?? ""
            let listings = p["listings"] as? [String: [String: Any]]
            let title = listings?.values.first?["title"] as? String ?? ""
            print("  \(sku)  [\(status)]  \(price) \(currency)  \(title)")
        }
    }
}

// MARK: - get

struct AndroidIAPGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show details of an in-app product"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product SKU")
    var sku: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching \(sku)")
        let p = try await client.getIAP(packageName: pkg, sku: sku)

        let status   = p["status"] as? String ?? "-"
        let price    = (p["defaultPrice"] as? [String: Any])?["priceMicros"] as? String ?? "-"
        let currency = (p["defaultPrice"] as? [String: Any])?["currency"] as? String ?? ""
        let listings = p["listings"] as? [String: [String: Any]] ?? [:]

        print("\nsku: \(sku)")
        print("status: \(status)")
        print("price: \(price) \(currency)")

        if !listings.isEmpty {
            print("listings:")
            for (lang, l) in listings {
                let title = l["title"] as? String ?? ""
                let desc  = l["description"] as? String ?? ""
                print("  [\(lang)] \(title)")
                if !desc.isEmpty { print("    \(desc)") }
            }
        }
    }
}

// MARK: - activate

struct AndroidIAPActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Activate an in-app product"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product SKU")
    var sku: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Activating \(sku)")
        try await client.updateIAPStatus(packageName: pkg, sku: sku, status: "active")
        Logger.success("\(sku) activated")
    }
}

// MARK: - deactivate

struct AndroidIAPDeactivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deactivate",
        abstract: "Deactivate an in-app product"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product SKU")
    var sku: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Deactivating \(sku)")
        try await client.updateIAPStatus(packageName: pkg, sku: sku, status: "inactive")
        Logger.success("\(sku) deactivated")
    }
}

// MARK: - create

struct AndroidIAPCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new in-app product")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product SKU")
    var sku: String

    @Option(name: .long, help: "Product type: inapp or subs (default: inapp)")
    var productType: String = "inapp"

    @Option(name: .long, help: "Default price (e.g. 0.99)")
    var price: Double

    @Option(name: .long, help: "Currency code (e.g. USD)")
    var currency: String = "USD"

    @Option(name: .long, help: "Default title (English)")
    var title: String

    @Option(name: .long, help: "Default description (English)")
    var description: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Creating IAP product '\(sku)'")
        try await client.createIAP(
            packageName: pkg,
            sku: sku,
            productType: productType,
            defaultPrice: price,
            defaultPriceCurrency: currency,
            titles: ["en-US": title],
            descriptions: ["en-US": description]
        )
        Logger.success("IAP product '\(sku)' created")
    }
}

// MARK: - delete

struct AndroidIAPDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an in-app product")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Product SKU")
    var sku: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deleting IAP product '\(sku)'")
        try await client.deleteIAP(packageName: pkg, sku: sku)
        Logger.success("IAP product '\(sku)' deleted")
    }
}
