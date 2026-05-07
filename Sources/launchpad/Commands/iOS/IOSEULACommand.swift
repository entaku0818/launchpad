import ArgumentParser
import Foundation

struct IOSEULACommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eula",
        abstract: "Manage custom End User License Agreements",
        subcommands: [
            IOSEULAListCommand.self,
            IOSEULAGetCommand.self,
            IOSEULACreateCommand.self,
            IOSEULAUpdateCommand.self,
            IOSEULADeleteCommand.self,
        ]
    )
}

struct IOSEULAListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List EULAs for the account")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching EULAs")
        let eulas = try await client.listEULAs()

        if eulas.isEmpty { Logger.info("No EULAs found"); return }
        Logger.info("\(eulas.count) EULA(s)\n")
        for e in eulas {
            guard let id = e["id"] as? String,
                  let attrs = e["attributes"] as? [String: Any] else { continue }
            let territories = (attrs["territories"] as? [String] ?? []).joined(separator: ", ")
            let preview = (attrs["agreementText"] as? String ?? "").prefix(60)
            print("  id: \(id)")
            print("    territories: \(territories.isEmpty ? "all" : territories)")
            print("    text: \(preview)…\n")
        }
    }
}

struct IOSEULAGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show EULA details")

    @Option(name: .long, help: "EULA ID")
    var eulaID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching EULA \(eulaID)")
        let eula = try await client.getEULA(eulaID: eulaID)

        guard let attrs = eula["attributes"] as? [String: Any] else {
            Logger.error("EULA not found"); Foundation.exit(1)
        }
        let territories = (attrs["territories"] as? [String] ?? []).joined(separator: ", ")
        let text = attrs["agreementText"] as? String ?? "-"

        print("\nid:          \(eulaID)")
        print("territories: \(territories.isEmpty ? "all" : territories)")
        print("\n\(text)")
    }
}

struct IOSEULACreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a custom EULA")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Path to text file containing the EULA")
    var textFile: String

    @Option(name: .long, help: "Comma-separated territory codes (e.g. USA,JPN) or 'all'")
    var territories: String = "all"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let text = try String(contentsOfFile: textFile, encoding: .utf8)
        let territoryList: [String] = territories == "all" ? [] : territories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating EULA")
        let id = try await client.createEULA(appID: appID, agreementText: text, territories: territoryList)
        Logger.success("EULA created: \(id)")
    }
}

struct IOSEULAUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a EULA")

    @Option(name: .long, help: "EULA ID")
    var eulaID: String

    @Option(name: .long, help: "Path to text file containing the updated EULA")
    var textFile: String

    @Option(name: .long, help: "Comma-separated territory codes or 'all'")
    var territories: String = "all"

    mutating func run() async throws {
        DotEnv.load()
        let text = try String(contentsOfFile: textFile, encoding: .utf8)
        let territoryList: [String] = territories == "all" ? [] : territories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Updating EULA \(eulaID)")
        try await client.updateEULA(eulaID: eulaID, agreementText: text, territories: territoryList)
        Logger.success("EULA updated")
    }
}

struct IOSEULADeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a EULA")

    @Option(name: .long, help: "EULA ID")
    var eulaID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting EULA \(eulaID)")
        try await client.deleteEULA(eulaID: eulaID)
        Logger.success("EULA deleted")
    }
}
