import ArgumentParser
import Foundation

struct IOSBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build and archive iOS app"
    )

    @Option(name: .long, help: "Xcode project path (.xcodeproj)")
    var project: String

    @Option(name: .long, help: "Build scheme")
    var scheme: String

    @Option(name: .long, help: "Export method (app-store, ad-hoc, development)")
    var exportMethod: String = "app-store"

    mutating func run() throws {
        print("Building \(scheme) from \(project)...")
        // TODO: implement (#2)
    }
}
