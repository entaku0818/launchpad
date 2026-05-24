import ArgumentParser
import Foundation

struct IOSAgeRatingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "age-rating",
        abstract: "Show or set age rating declaration for the current App Store version",
        subcommands: [IOSAgeRatingGetCommand.self, IOSAgeRatingSetCleanCommand.self],
        defaultSubcommand: IOSAgeRatingGetCommand.self
    )
}

struct IOSAgeRatingGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show age rating declaration")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version (auto-detected if omitted)")
    var version: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)

        let versionID: String
        if let ver = version {
            versionID = try await client.getAppStoreVersion(appID: appID, version: ver)
        } else {
            Logger.step("Auto-detecting latest editable version")
            let found = try await client.getLatestEditableAppStoreVersion(appID: appID)
            Logger.info("Version: \(found.version)")
            versionID = found.id
        }

        Logger.step("Fetching age rating declaration")
        let declaration = try await client.getAgeRatingDeclaration(versionID: versionID)

        guard let attrs = declaration["attributes"] as? [String: Any] else {
            Logger.info("No age rating declaration found"); return
        }

        print()
        for (key, val) in attrs {
            let label = key.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            print("  \(label): \(val)")
        }
    }
}

// Sets all content categories to the minimum (none/false) — suitable for a clean utility/lifestyle app
struct IOSAgeRatingSetCleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-clean", abstract: "Set all age rating fields to minimum (4+ rating, no content flags)")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        // String enum: "NONE" | "INFREQUENT_OR_MILD" | "FREQUENT_OR_INTENSE"
        // Boolean: true | false
        let attrs: [String: Any] = [
            "gambling": false,
            "lootBox": false,
            "unrestrictedWebAccess": false,
            "userGeneratedContent": false,
            "advertising": false,
            "messagingAndChat": false,
            "ageAssurance": false,
            "healthOrWellnessTopics": false,
            "parentalControls": false,
            "contests": "NONE",
            "gamblingSimulated": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
            "matureOrSuggestiveThemes": "NONE",
            "violenceRealisticProlongedGraphicOrSadistic": "NONE",
            "sexualContentGraphicAndNudity": "NONE",
            "profanityOrCrudeHumor": "NONE",
            "horrorOrFearThemes": "NONE",
            "medicalOrTreatmentInformation": "NONE",
            "violenceRealistic": "NONE",
            "violenceCartoonOrFantasy": "NONE",
            "sexualContentOrNudity": "NONE",
            "gunsOrOtherWeapons": "NONE",
        ]

        Logger.step("Finding age rating declaration ID")
        let appID: String
        if let bid = bundleID {
            appID = try await client.findApp(bundleID: bid)
        } else {
            let cfg = Config.load().ios
            let b = cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()
            appID = try await client.findApp(bundleID: b)
        }

        var declarationID = try await client.getAgeRatingDeclarationIDFromAppInfo(appID: appID)
        if declarationID == nil {
            Logger.info("No ageRatingDeclaration found via appInfo, using version ID as fallback")
            declarationID = versionID
        }

        Logger.step("Setting age rating declaration to clean (4+) — id: \(declarationID!)")
        try await client.updateAgeRatingDeclaration(declarationID: declarationID!, attributes: attrs)
        Logger.success("Age rating declaration set (4+, no content flags)")
    }
}
