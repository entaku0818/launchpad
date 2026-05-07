import ArgumentParser
import Foundation

struct AndroidPricingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pricing",
        abstract: "Convert prices across Play Store regions"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Price in micros (e.g. 990000 = $0.99)")
    var priceMicros: Int

    @Option(name: .long, help: "Source currency code (e.g. USD)")
    var currency: String = "USD"

    @Option(name: .long, help: "Comma-separated region codes to convert to (e.g. JP,GB,DE). Leave empty for all.")
    var regions: String = ""

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let regionList = regions.isEmpty ? [] : regions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Converting \(priceMicros) micros \(currency) across regions")
        let converted = try await client.convertRegionPrices(packageName: pkg, priceMicros: priceMicros, currencyCode: currency, regionCodes: regionList)

        if converted.isEmpty { Logger.info("No converted prices returned"); return }
        Logger.info("Converted prices\n")
        let sorted = converted.sorted { $0.key < $1.key }
        for (region, priceInfo) in sorted {
            let micros   = priceInfo["priceMicros"] as? String ?? priceInfo["priceMicros"].map { "\($0)" } ?? "-"
            let cur      = priceInfo["currency"] as? String ?? "-"
            let amount   = (Int(micros) ?? 0)
            let formatted = String(format: "%.2f", Double(amount) / 1_000_000)
            print("  \(region)  \(cur) \(formatted)")
        }
    }
}
