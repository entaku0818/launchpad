import ArgumentParser
import Foundation

struct AndroidUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload AAB to Google Play"
    )

    @Option(name: .long, help: "Package name (e.g. com.example.app)")
    var packageName: String

    @Option(name: .long, help: "Track (internal, alpha, beta, production)")
    var track: String = "internal"

    @Option(name: .long, help: "Path to .aab file")
    var aab: String?

    @Flag(name: .long, help: "Upload metadata only (no binary)")
    var metadataOnly: Bool = false

    mutating func run() async throws {
        let client = try GooglePlayClient.fromEnvironment()

        if metadataOnly {
            print("Uploading metadata to Google Play (\(track))...")
            try await client.uploadMetadata(packageName: packageName, track: track)
        } else {
            guard let aabPath = aab else {
                throw LaunchpadError.fileNotFound("--aab is required")
            }
            print("Uploading \(aabPath) to Google Play (\(track))...")
            try await client.uploadAAB(packageName: packageName, aabPath: aabPath, track: track)
        }

        print("Upload complete.")
    }
}
