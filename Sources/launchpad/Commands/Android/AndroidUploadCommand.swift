import ArgumentParser
import Foundation

struct AndroidUploadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload to Google Play"
    )

    @Option(name: .long, help: "Track (internal, production)")
    var track: String = "internal"

    @Option(name: .long, help: "Path to .aab file")
    var aab: String?

    @Flag(name: .long, help: "Upload metadata only (no binary)")
    var metadataOnly: Bool = false

    mutating func run() throws {
        print("Uploading to Google Play (\(track))...")
        // TODO: implement (#7)
    }
}
