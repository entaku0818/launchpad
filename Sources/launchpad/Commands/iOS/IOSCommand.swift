import ArgumentParser

struct IOSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ios",
        abstract: "iOS release operations",
        subcommands: [
            IOSBuildCommand.self,
            IOSUploadCommand.self,
            IOSSubmitCommand.self,
            IOSMetadataCommand.self,
            IOSScreenshotsCommand.self,
            IOSPhasedReleaseCommand.self,
            IOSReviewsCommand.self,
            IOSScheduleCommand.self,
            IOSReviewStatusCommand.self,
        ]
    )
}
