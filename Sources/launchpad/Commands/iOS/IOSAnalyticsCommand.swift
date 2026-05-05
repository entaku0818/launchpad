import ArgumentParser
import Foundation

struct IOSAnalyticsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analytics",
        abstract: "Request and download App Store analytics reports",
        subcommands: [
            IOSAnalyticsRequestCommand.self,
            IOSAnalyticsListCommand.self,
            IOSAnalyticsDownloadCommand.self,
        ]
    )
}

// MARK: - request

struct IOSAnalyticsRequestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "request",
        abstract: "Create an ongoing analytics report request"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Creating analytics report request for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let requestID = try await client.requestAnalyticsReport(appID: appID, reportType: "APP_STORE_ENGAGEMENT", frequency: "DAILY")
        Logger.success("Report request created  id: \(requestID)")
        Logger.info("Use 'analytics list --request-id \(requestID)' to check available reports")
    }
}

// MARK: - list

struct IOSAnalyticsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available reports for a request"
    )

    @Option(name: .long, help: "Analytics report request ID")
    var requestID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching reports for request \(requestID)")
        let reports = try await client.getAnalyticsReports(requestID: requestID)

        if reports.isEmpty { Logger.info("No reports available yet (may take up to 24h)"); return }

        Logger.info("\(reports.count) report(s)\n")
        for r in reports {
            guard let id = r["id"] as? String,
                  let attrs = r["attributes"] as? [String: Any] else { continue }
            let name = attrs["name"] as? String ?? "-"
            let category = attrs["category"] as? String ?? "-"
            print("  \(name)  [\(category)]  id: \(id)")
        }
    }
}

// MARK: - download

struct IOSAnalyticsDownloadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download segments of an analytics report instance"
    )

    @Option(name: .long, help: "Analytics report ID (from analytics list)")
    var reportID: String

    @Option(name: .long, help: "Output directory (default: ./analytics)")
    var output: String = "./analytics"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching instances for report \(reportID)")
        let instances = try await client.getAnalyticsReportInstances(reportID: reportID)

        guard let latest = instances.first,
              let instanceID = latest["id"] as? String else {
            Logger.info("No instances available"); return
        }

        let attrs = latest["attributes"] as? [String: Any] ?? [:]
        let processingDate = attrs["processingDate"] as? String ?? "-"
        Logger.info("Latest instance: \(processingDate)  id: \(instanceID)")

        let segments = try await client.getAnalyticsReportSegments(instanceID: instanceID)
        if segments.isEmpty { Logger.info("No segments available"); return }

        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

        Logger.step("Downloading \(segments.count) segment(s) to \(output)/")
        for (i, seg) in segments.enumerated() {
            guard let segAttrs = seg["attributes"] as? [String: Any],
                  let urlString = segAttrs["url"] as? String,
                  let url = URL(string: urlString) else { continue }

            let (data, _) = try await URLSession.shared.data(from: url)
            let fileName = "\(output)/segment_\(i + 1).csv.gz"
            try data.write(to: URL(fileURLWithPath: fileName))
            Logger.success("Saved \(fileName) (\(data.count / 1024) KB)")
        }
    }
}
