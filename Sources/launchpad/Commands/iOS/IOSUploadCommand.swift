import ArgumentParser
import Foundation

struct IOSUploadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload IPA to TestFlight or App Store"
    )

    @Option(name: .long, help: "Path to .ipa file")
    var ipa: String

    @Flag(name: .long, help: "Upload to TestFlight (default: App Store)")
    var testflight: Bool = false

    mutating func run() throws {
        let creds = try ASCCredentials.fromEnvironment()
        let keyPath = try creds.writeKeyFile()

        print("Uploading \(ipa)...")
        try Shell.runLive([
            "xcrun", "altool",
            "--upload-app",
            "-f", ipa,
            "--apiKey", creds.keyID,
            "--apiIssuer", creds.issuerID,
            "--type", "ios",
        ])

        print("Upload complete.")
        _ = keyPath
    }
}
