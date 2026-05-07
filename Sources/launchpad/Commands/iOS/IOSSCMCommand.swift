import ArgumentParser
import Foundation

struct IOSSCMCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scm",
        abstract: "Browse source code managers, repositories, and git refs for Xcode Cloud",
        subcommands: [
            IOSSCMProvidersCommand.self,
            IOSSCMRepositoriesCommand.self,
            IOSSCMGitRefsCommand.self,
        ]
    )
}

struct IOSSCMProvidersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "providers", abstract: "List connected SCM providers (GitHub, Bitbucket, etc.)")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching SCM providers")
        let providers = try await client.listSCMProviders()

        if providers.isEmpty { Logger.info("No SCM providers connected"); return }
        Logger.info("\(providers.count) provider(s)\n")
        for p in providers {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let name = attrs["scmProviderType"] as? String ?? "-"
            print("  \(name)  id: \(id)")
        }
    }
}

struct IOSSCMRepositoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "repos", abstract: "List repositories for an SCM provider")

    @Option(name: .long, help: "SCM provider ID (from scm providers)")
    var providerID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching repositories for provider \(providerID)")
        let repos = try await client.listSCMRepositories(providerID: providerID)

        if repos.isEmpty { Logger.info("No repositories found"); return }
        Logger.info("\(repos.count) repository/repositories\n")
        for r in repos {
            guard let id = r["id"] as? String,
                  let attrs = r["attributes"] as? [String: Any] else { continue }
            let name = attrs["repositoryName"] as? String ?? "-"
            let org  = attrs["ownerName"] as? String ?? ""
            print("  \(org.isEmpty ? "" : "\(org)/")\(name)  id: \(id)")
        }
    }
}

struct IOSSCMGitRefsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "refs", abstract: "List git branches and tags for a repository")

    @Option(name: .long, help: "SCM repository ID (from scm repos)")
    var repositoryID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching git references for repository \(repositoryID)")
        let refs = try await client.listSCMGitReferences(repositoryID: repositoryID)

        if refs.isEmpty { Logger.info("No git references found"); return }
        Logger.info("\(refs.count) ref(s)\n")
        for r in refs {
            guard let id = r["id"] as? String,
                  let attrs = r["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let refKind = attrs["kind"] as? String ?? "-"
            print("  [\(refKind)] \(name)  id: \(id)")
        }
    }
}
