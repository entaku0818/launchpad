import ArgumentParser
import Foundation

struct IOSEncryptionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encryption",
        abstract: "Manage export compliance encryption declarations",
        subcommands: [
            IOSEncryptionListCommand.self,
            IOSEncryptionCreateCommand.self,
        ]
    )
}

struct IOSEncryptionListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List encryption declarations for an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching encryption declarations for \(bid)")
        let decls = try await client.listEncryptionDeclarations(appID: appID)

        if decls.isEmpty { Logger.info("No encryption declarations found"); return }
        Logger.info("\(decls.count) declaration(s)\n")
        for d in decls {
            guard let id = d["id"] as? String,
                  let attrs = d["attributes"] as? [String: Any] else { continue }
            let platform   = attrs["platform"] as? String ?? "-"
            let usesEnc    = attrs["usesEncryption"] as? Bool ?? false
            let exempt     = attrs["exempt"] as? Bool ?? false
            let codeValue  = attrs["appEncryptionDeclarationState"] as? String ?? "-"
            print("  [\(platform)] usesEncryption: \(usesEnc)  exempt: \(exempt)  state: \(codeValue)")
            print("    id: \(id)\n")
        }
    }
}

struct IOSEncryptionCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an encryption declaration")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "Platform: IOS, MAC_OS, TV_OS (default: IOS)")
    var platform: String = "IOS"

    @Flag(name: .long, help: "App uses encryption")
    var usesEncryption: Bool = false

    @Flag(name: .long, help: "Exempt from export compliance")
    var exempt: Bool = false

    @Flag(name: .long, help: "Contains proprietary cryptography")
    var proprietaryCrypto: Bool = false

    @Flag(name: .long, help: "Contains third-party cryptography")
    var thirdPartyCrypto: Bool = false

    @Flag(name: .long, help: "Available on French App Store")
    var frenchStore: Bool = false

    @Option(name: .long, help: "URL to compliance document")
    var documentURL: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Creating encryption declaration for \(bid)")
        let id = try await client.createEncryptionDeclaration(
            appID: appID,
            platform: platform,
            usesEncryption: usesEncryption,
            exempt: exempt,
            containsProprietaryCryptography: proprietaryCrypto,
            containsThirdPartyCryptography: thirdPartyCrypto,
            availableOnFrenchStore: frenchStore,
            documentURL: documentURL
        )
        Logger.success("Encryption declaration created: \(id)")
    }
}
