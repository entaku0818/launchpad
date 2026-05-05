import ArgumentParser
import Foundation

struct AndroidUsersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "users",
        abstract: "Manage Play Console team members and permissions",
        subcommands: [
            AndroidUsersListCommand.self,
            AndroidUsersGrantCommand.self,
        ]
    )
}

struct AndroidUsersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List Play Console users"
    )

    mutating func run() async throws {
        DotEnv.load()
        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Fetching Play Console users")
        let users = try await client.listUsers()

        if users.isEmpty { Logger.info("No users found"); return }

        Logger.info("\(users.count) user(s)\n")
        for u in users {
            let email = u["email"] as? String ?? "-"
            let grants = u["grants"] as? [[String: Any]] ?? []
            let apps = grants.compactMap { $0["packageName"] as? String }.joined(separator: ", ")
            print("  \(email)  apps: \(apps.isEmpty ? "all" : apps)")
        }
    }
}

struct AndroidUsersGrantCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grant",
        abstract: "Grant a user access to an app"
    )

    @Option(name: .long, help: "User email address")
    var email: String

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Permission role (e.g. CAN_REPLY_TO_REVIEWS, VIEW_FINANCIAL_DATA, MANAGE_PRODUCTION_RELEASES)")
    var role: String = "CAN_REPLY_TO_REVIEWS"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Granting \(role) to \(email) for \(pkg)")
        try await client.grantUser(email: email, packageName: pkg, role: role)
        Logger.success("Access granted")
    }
}
