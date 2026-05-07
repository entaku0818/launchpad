import ArgumentParser
import Foundation

struct IOSPerfMetricsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perf-metrics",
        abstract: "Show App Store performance and power metrics (CPU, battery, launch time, memory)",
        subcommands: [
            IOSPerfMetricsBuildCommand.self,
            IOSPerfMetricsAppCommand.self,
        ]
    )
}

// MARK: - build metrics

struct IOSPerfMetricsBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "build", abstract: "Show perf/power metrics for a specific build")

    @Option(name: .long, help: "Build ID (from ios builds list)")
    var buildID: String

    @Option(name: .long, help: "Comma-separated metric types: HANG_RATE,MEMORY,BATTERY,LAUNCH_TIME,DISK_WRITES,TERMINATIONS (omit for all)")
    var metrics: String?

    @Option(name: .long, help: "Device type filter (e.g. iPhone14,3)")
    var deviceType: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let metricList = metrics.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        Logger.step("Fetching performance metrics for build \(buildID)")
        let results = try await client.getPerfPowerMetrics(buildID: buildID, metricTypes: metricList, deviceType: deviceType)

        if results.isEmpty { Logger.info("No metrics available for this build"); return }
        printMetrics(results)
    }
}

// MARK: - app metrics

struct IOSPerfMetricsAppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app", abstract: "Show perf/power metrics aggregated across all builds of an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Comma-separated metric types: HANG_RATE,MEMORY,BATTERY,LAUNCH_TIME,DISK_WRITES,TERMINATIONS (omit for all)")
    var metrics: String?

    @Option(name: .long, help: "Device type filter (e.g. iPhone14,3)")
    var deviceType: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        let metricList = metrics.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        Logger.step("Fetching performance metrics for \(bid)")
        let results = try await client.getAppPerfPowerMetrics(appID: appID, metricTypes: metricList, deviceType: deviceType)

        if results.isEmpty { Logger.info("No metrics available"); return }
        printMetrics(results)
    }
}

// MARK: - shared output

private func printMetrics(_ results: [[String: Any]]) {
    Logger.info("\(results.count) metric dataset(s)\n")
    for r in results {
        guard let attrs = r["attributes"] as? [String: Any] else { continue }
        let metricType  = attrs["metricType"] as? String ?? "-"
        let platform    = attrs["platform"] as? String ?? "-"
        let deviceType  = attrs["deviceType"] as? String ?? ""
        let unit        = attrs["unitOfMeasure"] as? String ?? ""

        print("  [\(metricType)]  platform: \(platform)\(deviceType.isEmpty ? "" : "  device: \(deviceType)")  unit: \(unit)")

        if let datasets = attrs["datasets"] as? [[String: Any]] {
            for ds in datasets {
                let filterID  = ds["filterCriteria"] as? [String: Any]
                let buildVer  = filterID?["buildType"] as? String ?? ""
                let points    = ds["points"] as? [[String: Any]] ?? []
                if !buildVer.isEmpty { print("    buildType: \(buildVer)") }
                for point in points.prefix(5) {
                    let pct50 = (point["percentile50thValue"] as? Double).map { String(format: "%.2f", $0) } ?? "-"
                    let pct90 = (point["percentile90thValue"] as? Double).map { String(format: "%.2f", $0) } ?? "-"
                    let pct95 = (point["percentile95thValue"] as? Double).map { String(format: "%.2f", $0) } ?? "-"
                    print("    p50: \(pct50)  p90: \(pct90)  p95: \(pct95) \(unit)")
                }
            }
        }
        print("")
    }
}
