import ArgumentParser
import Foundation

struct IOSSubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit app for App Store review via ASC API"
    )

    @Option(name: .long, help: "App bundle ID (e.g. com.example.app)")
    var bundleID: String

    @Option(name: .long, help: "App version to submit (e.g. 1.2.0)")
    var version: String

    mutating func run() async throws {
        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        print("Finding app \(bundleID)...")
        let appID = try await client.findApp(bundleID: bundleID)

        print("Finding version \(version)...")
        let versionID = try await client.getAppStoreVersion(appID: appID, version: version)

        print("Submitting for review...")
        try await client.submitForReview(versionID: versionID)

        print("Done! \(bundleID) v\(version) submitted for review.")
    }
}
