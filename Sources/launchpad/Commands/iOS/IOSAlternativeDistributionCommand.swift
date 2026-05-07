import ArgumentParser
import Foundation

struct IOSAlternativeDistributionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alt-distribution",
        abstract: "Manage EU alternative app distribution (alternative marketplaces)",
        subcommands: [
            IOSAltDistPackagesCommand.self,
            IOSAltDistDomainsListCommand.self,
            IOSAltDistDomainsCreateCommand.self,
        ]
    )
}

struct IOSAltDistPackagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "packages", abstract: "List alternative distribution packages for an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching alternative distribution packages for \(bid)")
        let packages = try await client.listAlternativeDistributionPackages(appID: appID)

        if packages.isEmpty { Logger.info("No packages found"); return }
        Logger.info("\(packages.count) package(s)\n")
        for p in packages {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let version = attrs["version"] as? Int ?? 0
            print("  id: \(id)  version: \(version)")
        }
    }
}

struct IOSAltDistDomainsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "domains", abstract: "List registered alternative distribution domains")

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching alternative distribution domains")
        let domains = try await client.listAlternativeDistributionDomains()

        if domains.isEmpty { Logger.info("No domains registered"); return }
        Logger.info("\(domains.count) domain(s)\n")
        for d in domains {
            guard let id = d["id"] as? String,
                  let attrs = d["attributes"] as? [String: Any] else { continue }
            let name   = attrs["referenceName"] as? String ?? "-"
            let domain = attrs["domain"] as? String ?? "-"
            print("  \(name)  \(domain)  id: \(id)")
        }
    }
}

struct IOSAltDistDomainsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add-domain", abstract: "Register an alternative distribution domain")

    @Option(name: .long, help: "Reference name for the domain")
    var name: String

    @Option(name: .long, help: "Domain (e.g. marketplace.example.com)")
    var domain: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Registering domain '\(domain)'")
        let id = try await client.createAlternativeDistributionDomain(referenceName: name, domain: domain)
        Logger.success("Domain registered: \(id)")
    }
}
