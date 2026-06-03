import ArgumentParser
import CryptoKit
import Foundation

struct IOSScreenshotsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshots",
        abstract: "Upload screenshots from fastlane/screenshots/ to App Store Connect"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version [config: ios.project + ios.scheme]")
    var version: String?

    @Option(name: .long, help: "Path to screenshots directory")
    var screenshotsPath: String = "fastlane/screenshots"

    @Flag(name: .long, help: "Delete existing screenshots before uploading")
    var overwrite: Bool = false

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
        let versionID = try await client.getAppStoreVersion(appID: appID, version: ver)
        let localizations = try await client.getLocalizations(versionID: versionID)

        for loc in localizations {
            guard
                let locID = (loc["id"] as? String),
                let attrs = loc["attributes"] as? [String: Any],
                let locale = attrs["locale"] as? String
            else { continue }

            let localeDir = "\(screenshotsPath)/\(locale)"
            guard FileManager.default.fileExists(atPath: localeDir) else { continue }

            Logger.info("Processing screenshots for \(locale)...")
            let sets = try await client.getScreenshotSets(localizationID: locID)

            let imageFiles = try imageFiles(in: localeDir)
            guard !imageFiles.isEmpty else { continue }

            // Group local files by ASC display type (fastlane-style filenames
            // already embed the type, e.g. 0_APP_IPHONE_69_0.png).
            var filesByType: [String: [String]] = [:]
            for file in imageFiles {
                guard let dt = displayType(for: file) else {
                    Logger.warn("Skipping \(file): could not determine display type")
                    continue
                }
                filesByType[dt, default: []].append(file)
            }
            guard !filesByType.isEmpty else { continue }

            for (displayType, matchingFiles) in filesByType {
                // Find the existing set for this display type, or create it
                // (App Store Connect needs a set before screenshots can be added).
                let setID: String
                if let existing = sets.first(where: {
                    ($0["attributes"] as? [String: Any])?["screenshotDisplayType"] as? String == displayType
                }), let existingID = existing["id"] as? String {
                    setID = existingID
                } else {
                    Logger.info("Creating screenshot set for \(displayType)...")
                    setID = try await client.createScreenshotSet(localizationID: locID, screenshotDisplayType: displayType)
                }

                if overwrite {
                    Logger.info("Deleting existing screenshots for \(displayType)...")
                    let existing = try await client.getScreenshots(setID: setID)
                    for s in existing {
                        if let sid = s["id"] as? String {
                            try await client.deleteScreenshot(id: sid)
                        }
                    }
                }

                let sorted = matchingFiles.sorted()
                Logger.step("Uploading \(sorted.count) screenshot(s) for \(locale) / \(displayType)")
                for (index, file) in sorted.enumerated() {
                    let filePath = "\(localeDir)/\(file)"
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    let md5 = Insecure.MD5.hash(data: fileData).map { String(format: "%02x", $0) }.joined()

                    let progress = "[\(index + 1)/\(sorted.count)]"
                    Logger.info("\(progress) Uploading \(file)...")
                    let start = Date()
                    let (screenshotID, uploadURL) = try await client.reserveScreenshot(
                        setID: setID,
                        fileName: file,
                        fileSize: fileData.count
                    )

                    var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
                    uploadRequest.httpMethod = "PUT"
                    uploadRequest.setValue("image/png", forHTTPHeaderField: "Content-Type")
                    uploadRequest.httpBody = fileData
                    _ = try await URLSession.shared.data(for: uploadRequest)

                    try await client.commitScreenshot(id: screenshotID, md5: md5, fileSize: fileData.count)
                    let elapsed = Date().timeIntervalSince(start)
                    Logger.success("\(progress) Uploaded \(file) (\(String(format: "%.2f", elapsed)) secs)")
                }
            }

            Logger.success("Screenshots uploaded for \(locale).")
        }

        Logger.success("Screenshot upload complete.")
    }

    private func imageFiles(in dir: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") }
    }

    // ASC display types that may be embedded verbatim in a filename. Ordered
    // longest-first so a prefix (e.g. APP_IPAD_PRO_129) never shadows a more
    // specific match (APP_IPAD_PRO_3GEN_129).
    private static let knownDisplayTypes = [
        "APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_3GEN_11",
        "APP_IPAD_PRO_129", "APP_IPAD_105", "APP_IPAD_97",
        "APP_IPHONE_69", "APP_IPHONE_67", "APP_IPHONE_65",
        "APP_IPHONE_61", "APP_IPHONE_58", "APP_IPHONE_55", "APP_IPHONE_47",
    ]

    // Map a screenshot filename to its ASC display type, or nil if unknown.
    // First honors a type embedded by `deliver`/fastlane (0_APP_IPHONE_69_0.png),
    // then falls back to dimension tokens (iphone_6.7_01.png).
    private func displayType(for filename: String) -> String? {
        let upper = filename.uppercased()
        for type in Self.knownDisplayTypes where upper.contains(type) { return type }

        let name = filename.lowercased()
        if name.contains("6.9") { return "APP_IPHONE_69" }
        if name.contains("6.7") { return "APP_IPHONE_67" }
        if name.contains("6.5") { return "APP_IPHONE_65" }
        if name.contains("6.1") { return "APP_IPHONE_61" }
        if name.contains("5.5") { return "APP_IPHONE_55" }
        if name.contains("12.9") { return "APP_IPAD_PRO_3GEN_129" }
        if name.contains("ipad_pro_11") || name.contains("11inch") { return "APP_IPAD_PRO_3GEN_11" }
        return nil
    }
}
