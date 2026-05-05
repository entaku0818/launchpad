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
            AndroidIAPCommand.self,
            AndroidMappingCommand.self,
            AndroidUsersCommand.self,
            AndroidDeviceTiersCommand.self,
            AndroidTestersCommand.self,
            AndroidCountriesCommand.self,
            AndroidDataSafetyCommand.self,
            AndroidImagesCommand.self,
            AndroidOffersCommand.self,
            AndroidRefundsCommand.self,
            AndroidPublishingCommand.self,
            AndroidBuildsCommand.self,
        ]
    )
}
