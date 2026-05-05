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
            IOSBetaCommand.self,
            IOSEventsCommand.self,
            IOSPreviewsCommand.self,
            IOSPricingCommand.self,
            IOSProductPagesCommand.self,
            IOSProvisioningCommand.self,
            IOSSubscriptionGroupsCommand.self,
            IOSPromoCodesCommand.self,
            IOSAnalyticsCommand.self,
            IOSFinanceCommand.self,
            IOSWebhooksCommand.self,
            IOSPhasedReleaseCommand.self,
            IOSReviewsCommand.self,
            IOSScheduleCommand.self,
            IOSReviewStatusCommand.self,
        ]
    )
}
