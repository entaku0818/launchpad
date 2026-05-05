import ArgumentParser
import Foundation

struct IOSSubmitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit app for App Store review"
    )

    @Option(name: .long, help: "App version (e.g. 1.0.0)")
    var version: String

    @Flag(name: .long, help: "Automatic release after approval")
    var autoRelease: Bool = false

    mutating func run() throws {
        print("Submitting \(version) for review...")
        // TODO: implement (#1, #5)
    }
}
