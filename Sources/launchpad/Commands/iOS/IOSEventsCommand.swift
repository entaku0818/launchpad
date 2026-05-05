import ArgumentParser
import Foundation

struct IOSEventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Manage App Store in-app events",
        subcommands: [
            IOSEventsListCommand.self,
            IOSEventsGetCommand.self,
            IOSEventsPublishCommand.self,
            IOSEventsUnpublishCommand.self,
        ]
    )
}

// MARK: - list

struct IOSEventsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all in-app events"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching in-app events for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let events = try await client.getAppEvents(appID: appID)

        if events.isEmpty { Logger.info("No in-app events found"); return }

        Logger.info("\(events.count) event(s)\n")
        for e in events {
            guard let id = e["id"] as? String,
                  let attrs = e["attributes"] as? [String: Any] else { continue }
            let name  = attrs["referenceName"] as? String ?? "-"
            let state = attrs["eventState"] as? String ?? "-"
            let badge = attrs["badge"] as? String ?? ""
            let start = attrs["startDate"] as? String ?? "-"
            let end   = attrs["endDate"] as? String ?? "-"
            print("  \(name)  [\(state)]  badge: \(badge)")
            print("    id: \(id)  \(start) → \(end)\n")
        }
    }
}

// MARK: - get

struct IOSEventsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show details of an in-app event"
    )

    @Option(name: .long, help: "Event ID")
    var eventID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching event \(eventID)")
        let event = try await client.getAppEvent(eventID: eventID)

        guard let attrs = event["attributes"] as? [String: Any] else {
            Logger.error("Invalid response"); Foundation.exit(1)
        }

        let name  = attrs["referenceName"] as? String ?? "-"
        let state = attrs["eventState"] as? String ?? "-"
        let badge = attrs["badge"] as? String ?? "-"
        let start = attrs["startDate"] as? String ?? "-"
        let end   = attrs["endDate"] as? String ?? "-"

        print("\nreferenceName: \(name)")
        print("state:         \(state)")
        print("badge:         \(badge)")
        print("period:        \(start) → \(end)")

        if let included = (event["relationships"] as? [String: Any])?["localizations"] as? [String: Any],
           let locs = included["data"] as? [[String: Any]], !locs.isEmpty {
            print("localizations: \(locs.count) locale(s)")
        }
    }
}

// MARK: - publish

struct IOSEventsPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish an in-app event"
    )

    @Option(name: .long, help: "Event ID")
    var eventID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Publishing event \(eventID)")
        try await client.publishAppEvent(eventID: eventID)
        Logger.success("Event published")
    }
}

// MARK: - unpublish

struct IOSEventsUnpublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpublish",
        abstract: "Unpublish an in-app event"
    )

    @Option(name: .long, help: "Event ID")
    var eventID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Unpublishing event \(eventID)")
        try await client.unpublishAppEvent(eventID: eventID)
        Logger.success("Event unpublished")
    }
}
