import ArgumentParser
import Foundation

struct IOSSandboxTestersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sandbox-testers",
        abstract: "Manage sandbox test accounts for IAP testing",
        subcommands: [
            IOSSandboxTestersListCommand.self,
            IOSSandboxTestersCreateCommand.self,
            IOSSandboxTestersDeleteCommand.self,
        ]
    )
}

struct IOSSandboxTestersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List sandbox testers")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching sandbox testers")
        let testers = try await client.listSandboxTesters()

        if testers.isEmpty { Logger.info("No sandbox testers found"); return }
        Logger.info("\(testers.count) tester(s)\n")
        for t in testers {
            guard let id = t["id"] as? String,
                  let attrs = t["attributes"] as? [String: Any] else { continue }
            let first     = attrs["firstName"] as? String ?? ""
            let last      = attrs["lastName"] as? String ?? ""
            let appleID   = attrs["appleId"] as? String ?? "-"
            let territory = attrs["territory"] as? String ?? "-"
            print("  \(first) \(last)  \(appleID)  [\(territory)]  id: \(id)")
        }
    }
}

struct IOSSandboxTestersCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a sandbox tester account")

    @Option(name: .long, help: "First name")
    var firstName: String

    @Option(name: .long, help: "Last name")
    var lastName: String

    @Option(name: .long, help: "Apple ID email (must be unique and not a real account)")
    var email: String

    @Option(name: .long, help: "Password (min 8 chars, mixed case + number)")
    var password: String

    @Option(name: .long, help: "Store territory code (e.g. JPN, USA, GBR)")
    var territory: String = "USA"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating sandbox tester \(email)")
        let id = try await client.createSandboxTester(
            firstName: firstName, lastName: lastName,
            email: email, password: password, territory: territory
        )
        Logger.success("Sandbox tester created  id: \(id)")
    }
}

struct IOSSandboxTestersDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a sandbox tester")

    @Option(name: .long, help: "Sandbox tester ID")
    var testerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting sandbox tester \(testerID)")
        try await client.deleteSandboxTester(id: testerID)
        Logger.success("Deleted")
    }
}
