import ArgumentParser
import Foundation

struct IOSBetaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "beta",
        abstract: "Manage TestFlight beta testers and groups",
        subcommands: [
            IOSBetaGroupsCommand.self,
            IOSBetaTestersCommand.self,
            IOSBetaAddCommand.self,
            IOSBetaRemoveCommand.self,
            IOSBetaCreateGroupCommand.self,
            IOSBetaDeleteGroupCommand.self,
        ]
    )
}

// MARK: - groups

struct IOSBetaGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "groups",
        abstract: "List beta groups"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching beta groups for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let groups = try await client.getBetaGroups(appID: appID)

        if groups.isEmpty { Logger.info("No beta groups found"); return }

        for g in groups {
            guard let id = g["id"] as? String,
                  let attrs = g["attributes"] as? [String: Any],
                  let name = attrs["name"] as? String else { continue }
            let isInternal = attrs["isInternalGroup"] as? Bool ?? false
            let link = attrs["publicLink"] as? String
            let tag = isInternal ? "[internal]" : "[external]"
            print("  \(tag) \(name)  id: \(id)")
            if let link { print("         link: \(link)") }
        }
    }
}

// MARK: - testers

struct IOSBetaTestersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testers",
        abstract: "List testers in a beta group"
    )

    @Option(name: .long, help: "Beta group ID")
    var groupID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching testers in group \(groupID)")
        let testers = try await client.getBetaTesters(groupID: groupID)

        if testers.isEmpty { Logger.info("No testers in this group"); return }

        Logger.info("\(testers.count) tester(s)")
        for t in testers {
            guard let attrs = t["attributes"] as? [String: Any] else { continue }
            let email = attrs["email"] as? String ?? "-"
            let first = attrs["firstName"] as? String ?? ""
            let last  = attrs["lastName"]  as? String ?? ""
            let status = attrs["status"] as? String ?? ""
            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            print("  \(email)  \(name)  [\(status)]")
        }
    }
}

// MARK: - add

struct IOSBetaAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a tester to a beta group"
    )

    @Option(name: .long, help: "Beta group ID")
    var groupID: String

    @Option(name: .long, help: "Tester email address")
    var email: String

    @Option(name: .long, help: "First name (optional)")
    var firstName: String?

    @Option(name: .long, help: "Last name (optional)")
    var lastName: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Adding \(email) to group \(groupID)")
        try await client.addBetaTester(email: email, firstName: firstName, lastName: lastName, groupID: groupID)
        Logger.success("Invite sent to \(email)")
    }
}

// MARK: - remove

struct IOSBetaRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a tester from a beta group"
    )

    @Option(name: .long, help: "Beta group ID")
    var groupID: String

    @Option(name: .long, help: "Tester email address")
    var email: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Removing \(email) from group \(groupID)")
        try await client.removeBetaTester(email: email, groupID: groupID)
        Logger.success("Removed \(email)")
    }
}

// MARK: - create-group

struct IOSBetaCreateGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-group",
        abstract: "Create a new external beta group"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Group name")
    var name: String

    @Flag(name: .long, help: "Enable public link for the group")
    var publicLink: Bool = false

    @Flag(name: .long, help: "Enable tester feedback")
    var feedback: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating beta group '\(name)'")
        let id = try await client.createBetaGroup(appID: appID, name: name, publicLinkEnabled: publicLink, feedbackEnabled: feedback)
        Logger.success("Beta group created: \(id)")
    }
}

// MARK: - delete-group

struct IOSBetaDeleteGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-group",
        abstract: "Delete a beta group"
    )

    @Option(name: .long, help: "Beta group ID")
    var groupID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting beta group \(groupID)")
        try await client.deleteBetaGroup(groupID: groupID)
        Logger.success("Beta group deleted")
    }
}
