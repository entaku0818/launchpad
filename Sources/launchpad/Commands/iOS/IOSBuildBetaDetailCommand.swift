import ArgumentParser
import Foundation

struct IOSBuildBetaDetailCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-beta-detail",
        abstract: "View and update TestFlight build beta details (What's New, auto-notify)",
        subcommands: [
            IOSBuildBetaDetailGetCommand.self,
            IOSBuildBetaDetailUpdateCommand.self,
        ]
    )
}

struct IOSBuildBetaDetailGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show beta detail for a build")

    @Option(name: .long, help: "Build ID (from ios builds list)")
    var buildID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching beta detail for build \(buildID)")
        let detail = try await client.getBuildBetaDetail(buildID: buildID)

        guard let id = detail["id"] as? String,
              let attrs = detail["attributes"] as? [String: Any] else {
            Logger.info("No beta detail found"); return
        }
        let autoNotify = attrs["autoNotifyEnabled"] as? Bool ?? false
        let whatsNew   = attrs["whatsNew"] as? String ?? ""
        print("ID:              \(id)")
        print("autoNotifyEnabled: \(autoNotify)")
        if !whatsNew.isEmpty {
            print("What's New:\n\(whatsNew)")
        }
    }
}

struct IOSBuildBetaDetailUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update What's New or auto-notify for a build")

    @Option(name: .long, help: "Build beta detail ID (from get)")
    var detailID: String

    @Option(name: .long, help: "What's new text shown to testers")
    var whatsNew: String?

    @Flag(name: .long, help: "Enable auto-notification to testers")
    var autoNotify: Bool = false

    @Flag(name: .long, help: "Disable auto-notification to testers")
    var noAutoNotify: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let autoNotifyEnabled: Bool? = autoNotify ? true : (noAutoNotify ? false : nil)
        Logger.step("Updating build beta detail \(detailID)")
        try await client.updateBuildBetaDetail(detailID: detailID, whatsNew: whatsNew, autoNotifyEnabled: autoNotifyEnabled)
        Logger.success("Build beta detail updated")
    }
}
