import ArgumentParser

@main
@available(macOS 13, *)
struct Launchpad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad",
        abstract: "Personal iOS/Android release tool",
        subcommands: [InitCommand.self, IOSCommand.self, AndroidCommand.self]
    )
}
