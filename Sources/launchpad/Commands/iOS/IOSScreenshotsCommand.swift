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

            // group by display type (filename prefix like iPhone_6.5_01.png)
            for set in sets {
                guard
                    let setID = (set["id"] as? String),
                    let setAttrs = set["attributes"] as? [String: Any],
                    let displayType = setAttrs["screenshotDisplayType"] as? String
                else { continue }

                let matchingFiles = imageFiles.filter { self.displayType(for: $0) == displayType }
                guard !matchingFiles.isEmpty else { continue }

                if overwrite {
                    Logger.info("Deleting existing screenshots for \(displayType)...")
                    let existing = try await client.getScreenshots(setID: setID)
                    for s in existing {
                        if let sid = s["id"] as? String {
                            try await client.deleteScreenshot(id: sid)
                        }
                    }
                }

                for file in matchingFiles.sorted() {
                    let filePath = "\(localeDir)/\(file)"
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    let md5 = Insecure.MD5.hash(data: fileData).map { String(format: "%02x", $0) }.joined()

                    Logger.info("Uploading \(file)...")
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

    // Map filename prefix to ASC display type
    private func displayType(for filename: String) -> String {
        let name = filename.lowercased()
        if name.contains("iphone_6.7") || name.contains("6.7") { return "APP_IPHONE_67" }
        if name.contains("iphone_6.5") || name.contains("6.5") { return "APP_IPHONE_65" }
        if name.contains("iphone_5.5") || name.contains("5.5") { return "APP_IPHONE_55" }
        if name.contains("ipad_pro_12.9") || name.contains("12.9") { return "APP_IPAD_PRO_3GEN_129" }
        if name.contains("ipad_pro_11") || name.contains("11inch") { return "APP_IPAD_PRO_3GEN_11" }
        return "APP_IPHONE_65"
    }
}
