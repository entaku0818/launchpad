import ArgumentParser

struct AndroidCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "android",
        abstract: "Android release operations",
        subcommands: [
            AndroidBuildCommand.self,
            AndroidUploadCommand.self,
        ]
    )
}
