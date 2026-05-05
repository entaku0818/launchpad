import ArgumentParser
import Foundation

struct IOSUploadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload to TestFlight or App Store"
    )

    @Option(name: .long, help: "Path to .ipa file")
    var ipa: String

    @Flag(name: .long, help: "Upload to TestFlight only")
    var testflight: Bool = false

    mutating func run() throws {
        print("Uploading \(ipa)...")
        // TODO: implement (#3, #4)
    }
}
