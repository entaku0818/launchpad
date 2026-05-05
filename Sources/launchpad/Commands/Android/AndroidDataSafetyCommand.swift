import ArgumentParser
import Foundation

struct AndroidDataSafetyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "data-safety",
        abstract: "Show Play Store data safety declaration status"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching data safety info for \(pkg)")
        let info = try await client.getDataSafety(packageName: pkg)

        if info.isEmpty { Logger.info("No data safety declaration found"); return }

        func printField(_ label: String, _ key: String) {
            if let val = info[key] { print("  \(label): \(val)") }
        }

        print()
        printField("Status",           "safetyLabelsStatus")
        printField("Certification",    "certificationStatus")
        printField("Data collected",   "dataCollected")
        printField("Data shared",      "dataShared")
        printField("Security practices","securityPractices")

        if let dataTypes = info["dataTypes"] as? [[String: Any]], !dataTypes.isEmpty {
            print("\n  Data types declared: \(dataTypes.count)")
            for dt in dataTypes.prefix(5) {
                let name = dt["dataType"] as? String ?? "-"
                let collected = dt["collected"] as? Bool ?? false
                let shared = dt["shared"] as? Bool ?? false
                print("    \(name)  collected: \(collected)  shared: \(shared)")
            }
            if dataTypes.count > 5 { print("    ... and \(dataTypes.count - 5) more") }
        }

        Logger.info("\nManage full declaration at: https://play.google.com/console → App content → Data safety")
    }
}
