import ArgumentParser
import Foundation

struct IOSBetaLicenseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "beta-license",
        abstract: "Manage TestFlight custom beta license agreement",
        subcommands: [
            IOSBetaLicenseGetCommand.self,
            IOSBetaLicenseUpdateCommand.self,
        ]
    )
}

struct IOSBetaLicenseGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show current beta license agreement")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching beta license agreement for \(bid)")
        let agreement = try await client.getBetaLicenseAgreements(appID: appID)

        guard let id = agreement["id"] as? String,
              let attrs = agreement["attributes"] as? [String: Any] else {
            Logger.info("No beta license agreement found"); return
        }
        let text = attrs["agreementText"] as? String ?? "(empty)"
        print("\nid: \(id)\n")
        print(text)
    }
}

struct IOSBetaLicenseUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update the beta license agreement text")

    @Option(name: .long, help: "Beta license agreement ID (from beta-license get)")
    var agreementID: String

    @Option(name: .long, help: "Path to text file with the new agreement")
    var textFile: String

    mutating func run() async throws {
        DotEnv.load()
        let text = try String(contentsOfFile: textFile, encoding: .utf8)
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating beta license agreement \(agreementID)")
        try await client.updateBetaLicenseAgreement(agreementID: agreementID, agreementText: text)
        Logger.success("Beta license agreement updated")
    }
}
