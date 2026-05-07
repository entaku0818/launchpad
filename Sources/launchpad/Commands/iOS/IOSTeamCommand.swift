import ArgumentParser
import Foundation

struct IOSTeamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "team",
        abstract: "Manage App Store Connect team members",
        subcommands: [
            IOSTeamListCommand.self,
            IOSTeamInviteCommand.self,
            IOSTeamRemoveCommand.self,
            IOSTeamInvitationsListCommand.self,
            IOSTeamInvitationsCancelCommand.self,
        ]
    )
}

struct IOSTeamListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List team members")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching team members")
        let users = try await client.listTeamUsers()

        if users.isEmpty { Logger.info("No users found"); return }
        Logger.info("\(users.count) member(s)\n")
        for u in users {
            guard let id = u["id"] as? String,
                  let attrs = u["attributes"] as? [String: Any] else { continue }
            let username  = attrs["username"] as? String ?? "-"
            let first     = attrs["firstName"] as? String ?? ""
            let last      = attrs["lastName"] as? String ?? ""
            let roles     = (attrs["roles"] as? [String] ?? []).joined(separator: ", ")
            let allApps   = attrs["allAppsVisible"] as? Bool ?? false
            print("  \(first) \(last)  <\(username)>")
            print("    roles: \(roles)  allApps: \(allApps)  id: \(id)\n")
        }
    }
}

struct IOSTeamInviteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "invite", abstract: "Invite a new team member")

    @Option(name: .long, help: "Email address")
    var email: String

    @Option(name: .long, help: "First name")
    var firstName: String

    @Option(name: .long, help: "Last name")
    var lastName: String

    @Option(name: .long, help: "Comma-separated roles: ADMIN, FINANCE, TECHNICAL, SALES, MARKETING, ACCOUNT_HOLDER, DEVELOPER, APP_MANAGER, CUSTOMER_SUPPORT, ACCESS_TO_REPORTS, CREATE_APPS")
    var roles: String = "DEVELOPER"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let roleList = roles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        Logger.step("Inviting \(email) with roles: \(roleList.joined(separator: ", "))")
        try await client.inviteUser(email: email, firstName: firstName, lastName: lastName, roles: roleList)
        Logger.success("Invitation sent to \(email)")
    }
}

struct IOSTeamRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a team member")

    @Option(name: .long, help: "User ID (from team list)")
    var userID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Removing user \(userID)")
        try await client.removeUser(userID: userID)
        Logger.success("User removed")
    }
}

struct IOSTeamInvitationsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "invitations", abstract: "List pending user invitations")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching pending invitations")
        let invitations = try await client.listUserInvitations()

        if invitations.isEmpty { Logger.info("No pending invitations"); return }
        Logger.info("\(invitations.count) invitation(s)\n")
        for inv in invitations {
            guard let id = inv["id"] as? String,
                  let attrs = inv["attributes"] as? [String: Any] else { continue }
            let email   = attrs["email"] as? String ?? "-"
            let first   = attrs["firstName"] as? String ?? ""
            let last    = attrs["lastName"] as? String ?? ""
            let roles   = (attrs["roles"] as? [String] ?? []).joined(separator: ", ")
            let expires = attrs["expirationDate"] as? String ?? "-"
            print("  \(first) \(last)  <\(email)>")
            print("    roles: \(roles)  expires: \(expires)  id: \(id)\n")
        }
    }
}

struct IOSTeamInvitationsCancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cancel-invitation", abstract: "Cancel a pending invitation")

    @Option(name: .long, help: "Invitation ID (from team invitations)")
    var invitationID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Cancelling invitation \(invitationID)")
        try await client.cancelUserInvitation(invitationID: invitationID)
        Logger.success("Invitation cancelled")
    }
}
