import ArgumentParser
import Foundation

struct IOSUploadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload IPA to TestFlight or App Store"
    )

    @Option(name: .long, help: "Path to .ipa file")
    var ipa: String?

    @Option(name: .long, help: "Scheme name (used to locate IPA in build output) [config: ios.scheme]")
    var scheme: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load().ios

        let sch = scheme ?? cfg?.scheme
        let ipaPath: String
        if let ipa {
            ipaPath = ipa
        } else if let sch {
            let out = cfg?.output ?? "./build"
            ipaPath = "\(out)/export/\(sch).ipa"
        } else {
            Logger.error("--ipa or ios.scheme in .launchpadrc required")
            Foundation.exit(1)
        }

        let creds = try ASCCredentials.fromEnvironment()
        _ = try creds.writeKeyFile()

        Logger.step("Uploading \(ipaPath)")
        try Shell.runLive([
            "xcrun", "altool",
            "--upload-app",
            "-f", ipaPath,
            "--apiKey", creds.keyID,
            "--apiIssuer", creds.issuerID,
            "--type", "ios",
        ])

        Logger.success("Upload complete.")
    }
}
