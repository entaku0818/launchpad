import ArgumentParser
import Foundation

struct IOSProductPagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "product-pages",
        abstract: "Manage custom product pages for A/B store listing",
        subcommands: [
            IOSProductPagesListCommand.self,
        ]
    )
}

struct IOSProductPagesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List custom product pages"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching custom product pages for \(bid)")
        let appID = try await client.findApp(bundleID: bid)
        let pages = try await client.getCustomProductPages(appID: appID)

        if pages.isEmpty { Logger.info("No custom product pages found"); return }

        Logger.info("\(pages.count) page(s)\n")
        for p in pages {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let url     = attrs["url"] as? String ?? ""
            let visible = attrs["visible"] as? Bool ?? false
            print("  \(name)  [visible: \(visible)]")
            print("    id: \(id)")
            if !url.isEmpty { print("    url: \(url)") }
        }
    }
}
