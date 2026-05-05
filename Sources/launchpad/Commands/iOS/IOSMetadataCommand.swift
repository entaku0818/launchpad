import ArgumentParser
import Foundation

struct IOSMetadataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata",
        abstract: "Update App Store metadata from fastlane/metadata/ directory"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version [config: ios.project + ios.scheme]")
    var version: String?

    @Option(name: .long, help: "Path to metadata directory")
    var metadataPath: String = "fastlane/metadata"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        let creds = try ASCCredentials.fromEnvironment()
        let client = ASCAPIClient(credentials: creds)

        let ver: String
        if let version {
            ver = version
        } else if let proj = cfg?.project, let tgt = cfg?.scheme {
            ver = try XcodeProject.versionNumber(project: proj, target: tgt)
        } else {
            Logger.error("--version or ios.project + ios.scheme in .launchpadrc required")
            Foundation.exit(1)
        }

        Logger.step("Fetching app info for \(bid) v\(ver)")
        let appID = try await client.findApp(bundleID: bid)
        let versionID: String
        if version != nil {
            versionID = try await client.getAppStoreVersion(appID: appID, version: ver)
        } else {
            let found = try await client.getLatestEditableAppStoreVersion(appID: appID)
            Logger.info("Auto-detected editable version: \(found.version)")
            versionID = found.id
        }
        let localizations = try await client.getLocalizations(versionID: versionID)

        Logger.info("Found \(localizations.count) localizations")

        for loc in localizations {
            guard
                let locID = (loc["id"] as? String),
                let attrs = loc["attributes"] as? [String: Any],
                let locale = attrs["locale"] as? String
            else { continue }

            let localeDir = "\(metadataPath)/\(locale)"
            guard FileManager.default.fileExists(atPath: localeDir) else { continue }

            Logger.info("Updating \(locale)...")
            var updates: [String: Any] = [:]

            let fields: [(file: String, key: String)] = [
                ("description.txt",    "description"),
                ("keywords.txt",       "keywords"),
                ("release_notes.txt",  "whatsNew"),
                ("promotional_text.txt", "promotionalText"),
                ("support_url.txt",    "supportUrl"),
                ("marketing_url.txt",  "marketingUrl"),
            ]

            for (file, key) in fields {
                let filePath = "\(localeDir)/\(file)"
                if let text = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    updates[key] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if !updates.isEmpty {
                try await client.updateLocalization(localizationID: locID, attributes: updates)
                Logger.success("Updated \(locale): \(updates.keys.joined(separator: ", "))")
            }
        }

        Logger.success("Metadata update complete.")
    }
}
