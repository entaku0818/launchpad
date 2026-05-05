import ArgumentParser
import Foundation

struct AndroidBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build Android APK or AAB"
    )

    @Option(name: .long, help: "Project directory")
    var projectDir: String = "./"

    @Flag(name: .long, help: "Build release AAB (default: debug APK)")
    var release: Bool = false

    mutating func run() throws {
        let buildType = release ? "release AAB" : "debug APK"
        print("Building \(buildType) in \(projectDir)...")
        // TODO: implement (#6)
    }
}
