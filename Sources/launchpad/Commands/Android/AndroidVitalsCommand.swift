import ArgumentParser
import Foundation

struct AndroidVitalsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vitals",
        abstract: "Android vitals: crash rate, ANR rate, startup speed, and battery metrics",
        subcommands: [
            AndroidVitalsCrashCommand.self,
            AndroidVitalsANRCommand.self,
            AndroidVitalsStartupCommand.self,
            AndroidVitalsRenderingCommand.self,
            AndroidVitalsWakeupCommand.self,
            AndroidVitalsWakelockCommand.self,
            AndroidVitalsAnomaliesCommand.self,
        ]
    )
}

private func printMetricSet(_ result: [String: Any], label: String) {
    let rows = result["rows"] as? [[String: Any]] ?? []
    if rows.isEmpty { Logger.info("No data available for the period"); return }
    Logger.info("\(label) — \(rows.count) day(s) of data\n")
    for row in rows {
        let dims    = row["dimensions"] as? [[String: Any]] ?? []
        let metrics = row["metrics"] as? [[String: Any]] ?? []
        let date    = dims.first(where: { $0["dimension"] as? String == "date" })?["stringValue"] as? String ?? ""
        let values  = metrics.compactMap { m -> String? in
            guard let name = m["metric"] as? String else { return nil }
            let val = (m["decimalValue"] as? [String: Any])?["value"] as? String ?? m["integerValue"] as? String ?? "-"
            return "\(name): \(val)"
        }.joined(separator: "  ")
        print("  \(date.isEmpty ? "" : "[\(date)]  ")\(values)")
    }
}

struct AndroidVitalsCrashCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "crashes", abstract: "Show crash rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching crash rate for \(pkg) (last \(days) days)")
        let result = try await client.queryCrashRate(packageName: pkg, days: days)
        printMetricSet(result, label: "Crash Rate")
    }
}

struct AndroidVitalsANRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "anr", abstract: "Show ANR rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching ANR rate for \(pkg) (last \(days) days)")
        let result = try await client.queryANRRate(packageName: pkg, days: days)
        printMetricSet(result, label: "ANR Rate")
    }
}

struct AndroidVitalsStartupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "startup", abstract: "Show slow start rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching slow start rate for \(pkg) (last \(days) days)")
        let result = try await client.querySlowStartRate(packageName: pkg, days: days)
        printMetricSet(result, label: "Slow Start Rate")
    }
}

struct AndroidVitalsRenderingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rendering", abstract: "Show slow rendering rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching slow rendering rate for \(pkg) (last \(days) days)")
        let result = try await client.querySlowRenderingRate(packageName: pkg, days: days)
        printMetricSet(result, label: "Slow Rendering Rate")
    }
}

struct AndroidVitalsWakeupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "wakeups", abstract: "Show excessive wakeup rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching excessive wakeup rate for \(pkg) (last \(days) days)")
        let result = try await client.queryExcessiveWakeupRate(packageName: pkg, days: days)
        printMetricSet(result, label: "Excessive Wakeup Rate")
    }
}

struct AndroidVitalsWakelockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "wakelock", abstract: "Show stuck background wakelock rate over the last N days")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Number of days to query (default: 7)")
    var days: Int = 7

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching stuck background wakelock rate for \(pkg) (last \(days) days)")
        let result = try await client.queryStuckWakelockRate(packageName: pkg, days: days)
        printMetricSet(result, label: "Stuck Wakelock Rate")
    }
}

struct AndroidVitalsAnomaliesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "anomalies", abstract: "List metric anomalies detected by Google Play")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try PlayReportingClient.fromEnvironment()
        Logger.step("Fetching anomalies for \(pkg)")
        let anomalies = try await client.listAnomalies(packageName: pkg)

        if anomalies.isEmpty { Logger.info("No anomalies detected"); return }
        Logger.info("\(anomalies.count) anomaly/anomalies\n")
        for a in anomalies {
            let metric    = a["metricSetResource"] as? String ?? "-"
            let dimension = a["dimensionValue"] as? [String: Any]
            let value     = dimension?["stringValue"] as? String ?? ""
            print("  \(metric)\(value.isEmpty ? "" : " [\(value)]")")
        }
    }
}
