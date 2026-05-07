import ArgumentParser
import Foundation

struct IOSExperimentsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "experiments",
        abstract: "Manage Product Page Optimization A/B experiments",
        subcommands: [
            IOSExperimentsListCommand.self,
            IOSExperimentsCreateCommand.self,
            IOSExperimentsStartCommand.self,
            IOSExperimentsDeleteCommand.self,
        ]
    )
}

struct IOSExperimentsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List experiments for an App Store version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching experiments for version \(versionID)")
        let experiments = try await client.listAppStoreVersionExperiments(versionID: versionID)

        if experiments.isEmpty { Logger.info("No experiments found"); return }
        Logger.info("\(experiments.count) experiment(s)\n")
        for e in experiments {
            guard let id = e["id"] as? String,
                  let attrs = e["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let state   = attrs["state"] as? String ?? "-"
            let started = attrs["started"] as? Bool ?? false
            print("  \(name)  state: \(state)  started: \(started)")
            print("    id: \(id)")
        }
    }
}

struct IOSExperimentsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new product page A/B experiment")

    @Option(name: .long, help: "App Store version ID")
    var versionID: String

    @Option(name: .long, help: "Experiment name")
    var name: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating experiment '\(name)'")
        let id = try await client.createProductPageExperiment(versionID: versionID, name: name)
        Logger.success("Experiment created: \(id)")
    }
}

struct IOSExperimentsStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start a product page experiment")

    @Option(name: .long, help: "Experiment ID")
    var experimentID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Starting experiment \(experimentID)")
        try await client.startProductPageExperiment(experimentID: experimentID)
        Logger.success("Experiment started")
    }
}

struct IOSExperimentsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a product page experiment")

    @Option(name: .long, help: "Experiment ID")
    var experimentID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting experiment \(experimentID)")
        try await client.deleteProductPageExperiment(experimentID: experimentID)
        Logger.success("Experiment deleted")
    }
}
