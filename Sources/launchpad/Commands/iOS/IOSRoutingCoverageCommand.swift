import ArgumentParser
import Foundation

struct IOSRoutingCoverageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "routing-coverage",
        abstract: "Manage routing app coverage file for navigation apps",
        subcommands: [
            IOSRoutingCoverageGetCommand.self,
            IOSRoutingCoverageUploadCommand.self,
            IOSRoutingCoverageDeleteCommand.self,
        ]
    )
}

struct IOSRoutingCoverageGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show routing coverage info for an App Store version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching routing app coverage for version \(versionID)")
        guard let coverage = try await client.getRoutingAppCoverage(versionID: versionID) else {
            Logger.info("No routing coverage file found for this version")
            return
        }
        let id    = coverage["id"] as? String ?? "-"
        let attrs = coverage["attributes"] as? [String: Any] ?? [:]
        let name  = attrs["fileName"] as? String ?? "-"
        let size  = attrs["fileSize"] as? Int ?? 0
        let state = attrs["assetDeliveryState"] as? [String: Any]
        let stateVal = state?["state"] as? String ?? "-"
        print("ID:    \(id)")
        print("File:  \(name)  (\(size) bytes)")
        print("State: \(stateVal)")
    }
}

struct IOSRoutingCoverageUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload a routing coverage file (.geojson)")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    @Option(name: .long, help: "Path to .geojson coverage file")
    var file: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Uploading routing coverage from \(file)")
        let id = try await client.uploadRoutingAppCoverage(versionID: versionID, filePath: file)
        Logger.success("Routing coverage uploaded: \(id)")
    }
}

struct IOSRoutingCoverageDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a routing coverage file")

    @Option(name: .long, help: "Routing coverage ID (from routing-coverage get)")
    var coverageID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting routing coverage \(coverageID)")
        try await client.deleteRoutingAppCoverage(coverageID: coverageID)
        Logger.success("Routing coverage deleted")
    }
}
