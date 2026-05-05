import ArgumentParser

struct Launchpad: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad",
        abstract: "Personal iOS/Android release tool",
        subcommands: [IOSCommand.self, AndroidCommand.self]
    )
}

Launchpad.main()
