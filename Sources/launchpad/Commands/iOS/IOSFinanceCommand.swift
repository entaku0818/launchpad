import ArgumentParser
import Foundation

struct IOSFinanceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finance",
        abstract: "Download App Store financial reports"
    )

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
