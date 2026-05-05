import ArgumentParser
import Foundation

struct IOSAgeRatingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "age-rating",
        abstract: "Show age rating declaration for the current App Store version"
    )

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
        let skip = ["gamblingAndContests", "matureOrSuggestiveThemes", "unrestrictedWebAccess",
                    "alcoholTobaccoOrDrugUseOrReferences", "medicalOrTreatmentInformation",
                    "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic",
                    "horrorOrFearThemes", "profanityOrCrudeHumor", "kidsAgeBand",
                    "seventeenPlus", "sexualContentGraphicAndNudity", "contests", "gambling"]
        for key in skip {
            if let val = attrs[key] {
                let label = key.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                print("  \(label): \(val)")
            }
        }
    }
}
