import ArgumentParser

struct AndroidCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "android",
        abstract: "Android release operations",
        subcommands: [
            AndroidBuildCommand.self,
            AndroidUploadCommand.self,
            AndroidPromoteCommand.self,
            AndroidRolloutCommand.self,
            AndroidReviewsCommand.self,
            AndroidShareCommand.self,
            AndroidRecoverCommand.self,
            AndroidSubscriptionsCommand.self,
        ]
    )
}
