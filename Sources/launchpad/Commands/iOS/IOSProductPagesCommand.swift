import ArgumentParser
import Foundation

struct IOSProductPagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "product-pages",
        abstract: "Manage custom product pages for A/B store listing",
        subcommands: [
            IOSProductPagesListCommand.self,
            IOSProductPagesCreateCommand.self,
            IOSProductPagesSetVisibleCommand.self,
            IOSProductPagesDeleteCommand.self,
            IOSProductPagesVersionsCommand.self,
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

struct IOSProductPagesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a custom product page")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Display name for the custom product page")
    var name: String

    @Option(name: .long, help: "Deep link URL for the page (optional)")
    var url: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating custom product page '\(name)'")
        let id = try await client.createCustomProductPage(appID: appID, name: name, url: url)
        Logger.success("Custom product page created: \(id)")
    }
}

struct IOSProductPagesSetVisibleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-visible", abstract: "Show or hide a custom product page")

    @Option(name: .long, help: "Custom product page ID (from list)")
    var pageID: String

    @Flag(name: .long, help: "Make page visible")
    var visible: Bool = false

    @Flag(name: .long, help: "Hide page")
    var hidden: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        guard visible || hidden else {
            Logger.error("Pass --visible or --hidden"); Foundation.exit(1)
        }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("\(visible ? "Showing" : "Hiding") custom product page \(pageID)")
        try await client.updateCustomProductPageVisibility(pageID: pageID, visible: visible)
        Logger.success("Visibility updated")
    }
}

struct IOSProductPagesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a custom product page")

    @Option(name: .long, help: "Custom product page ID (from list)")
    var pageID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting custom product page \(pageID)")
        try await client.deleteCustomProductPage(pageID: pageID)
        Logger.success("Custom product page deleted")
    }
}

struct IOSProductPagesVersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "versions", abstract: "List versions of a custom product page")

    @Option(name: .long, help: "Custom product page ID (from list)")
    var pageID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching versions for custom product page \(pageID)")
        let versions = try await client.listCustomProductPageVersions(pageID: pageID)

        if versions.isEmpty { Logger.info("No versions found"); return }
        Logger.info("\(versions.count) version(s)\n")
        for v in versions {
            guard let id = v["id"] as? String,
                  let attrs = v["attributes"] as? [String: Any] else { continue }
            let state = attrs["state"] as? String ?? "-"
            print("  id: \(id)  state: \(state)")
        }
    }
}
