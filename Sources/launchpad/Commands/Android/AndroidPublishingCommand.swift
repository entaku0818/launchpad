import ArgumentParser
import Foundation

struct AndroidPublishingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publishing",
        abstract: "Manage Play Store managed publishing (manual release control)",
        subcommands: [
            AndroidPublishingStatusCommand.self,
            AndroidPublishingEnableCommand.self,
            AndroidPublishingDisableCommand.self,
        ]
    )
}

private let managedPublishingUnsupportedMessage = """
Managed Publishing is not exposed by the Google Play Developer API — there is no \
`managedPublishing` endpoint in the current androidpublisher v3 discovery document. \
This is a Play Console UI-only feature and cannot be controlled from launchpad. \
Toggle it manually in Play Console under Setup > Advanced settings > Publishing overview.
"""

struct AndroidPublishingStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show managed publishing status")

    mutating func run() async throws {
        throw LaunchpadError.unsupported(managedPublishingUnsupportedMessage)
    }
}

struct AndroidPublishingEnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Enable managed publishing (require manual publish)")

    mutating func run() async throws {
        throw LaunchpadError.unsupported(managedPublishingUnsupportedMessage)
    }
}

struct AndroidPublishingDisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disable", abstract: "Disable managed publishing (auto-publish after review)")

    mutating func run() async throws {
        throw LaunchpadError.unsupported(managedPublishingUnsupportedMessage)
    }
}
