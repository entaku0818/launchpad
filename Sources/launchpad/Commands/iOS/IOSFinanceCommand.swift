import ArgumentParser
import Foundation

struct IOSFinanceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finance",
        abstract: "Download App Store financial and sales reports",
        subcommands: [
            IOSFinanceFinancialCommand.self,
            IOSFinanceSalesCommand.self,
        ]
    )
}

struct IOSFinanceFinancialCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "financial", abstract: "Download monthly financial report")

    @Option(name: .long, help: "Vendor number (found in App Store Connect > Payments and Financial Reports)")
    var vendorNumber: String

    @Option(name: .long, help: "Report month in YYYY-MM format (e.g. 2026-04)")
    var date: String

    @Option(name: .long, help: "Region code (default: ZZ for worldwide)")
    var region: String = "ZZ"

    @Option(name: .long, help: "Output file path (default: finance_<date>.tsv)")
    var output: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Downloading financial report for \(date) region: \(region)")
        let content = try await client.downloadFinanceReport(vendorNumber: vendorNumber, reportDate: date, regionCode: region)
        let outPath = output ?? "finance_\(date)_\(region).tsv"
        try content.write(toFile: outPath, atomically: true, encoding: .utf8)
        Logger.success("Saved to \(outPath) (\(content.count / 1024) KB)")
    }
}

struct IOSFinanceSalesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sales", abstract: "Download sales and trends report")

    @Option(name: .long, help: "Vendor number")
    var vendorNumber: String

    @Option(name: .long, help: "Report type: SALES, SUBSCRIPTION, SUBSCRIPTION_EVENT, SUBSCRIBER, NEWSSTAND, PRE_ORDER (default: SALES)")
    var reportType: String = "SALES"

    @Option(name: .long, help: "Report sub-type: SUMMARY, DETAILED, OPT_IN (default: SUMMARY)")
    var subType: String = "SUMMARY"

    @Option(name: .long, help: "Frequency: DAILY, WEEKLY, MONTHLY, YEARLY (default: DAILY)")
    var frequency: String = "DAILY"

    @Option(name: .long, help: "Report date (YYYY-MM-DD for daily, YYYY-MM for monthly)")
    var date: String

    @Option(name: .long, help: "Output file path (default: sales_<date>.tsv)")
    var output: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Downloading \(reportType)/\(subType)/\(frequency) sales report for \(date)")
        let content = try await client.downloadSalesReport(
            vendorNumber: vendorNumber,
            reportType: reportType,
            reportSubType: subType,
            frequency: frequency,
            reportDate: date
        )
        let outPath = output ?? "sales_\(date).tsv"
        try content.write(toFile: outPath, atomically: true, encoding: .utf8)
        Logger.success("Saved to \(outPath) (\(content.count / 1024) KB)")
    }
}
