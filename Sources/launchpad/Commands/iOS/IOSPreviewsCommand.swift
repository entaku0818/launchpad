import ArgumentParser
import CryptoKit
import Foundation

struct IOSPreviewsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "previews",
        abstract: "Manage App Store preview videos",
        subcommands: [
            IOSPreviewsListCommand.self,
            IOSPreviewsUploadCommand.self,
            IOSPreviewsDeleteCommand.self,
        ]
    )
}

// MARK: - list

struct IOSPreviewsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List preview videos for each locale"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version (auto-read from xcodeproj if omitted)")
    var version: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        let ver = try resolveVersion(version: version, cfg: cfg)
        let appID = try await client.findApp(bundleID: bid)
        let versionID = try await client.getAppStoreVersion(appID: appID, version: ver)
        let localizations = try await client.getLocalizations(versionID: versionID)

        var found = false
        for loc in localizations {
            guard let locID = loc["id"] as? String,
                  let locale = (loc["attributes"] as? [String: Any])?["locale"] as? String else { continue }
            let sets = try await client.getPreviewSets(localizationID: locID)
            for set in sets {
                guard let setID = set["id"] as? String,
                      let displayType = (set["attributes"] as? [String: Any])?["previewType"] as? String else { continue }
                let previews = try await client.getPreviews(setID: setID)
                guard !previews.isEmpty else { continue }
                found = true
                print("\n[\(locale)] \(displayType)")
                for p in previews {
                    guard let pid = p["id"] as? String,
                          let attrs = p["attributes"] as? [String: Any] else { continue }
                    let name = attrs["fileName"] as? String ?? "-"
                    let state = attrs["assetDeliveryState"] as? [String: Any]
                    let status = state?["state"] as? String ?? "-"
                    print("  \(name)  [\(status)]  id: \(pid)")
                }
            }
        }
        if !found { Logger.info("No preview videos found") }
    }
}

// MARK: - upload

struct IOSPreviewsUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload a preview video for a locale and display type"
    )

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    @Option(name: .long, help: "App version (auto-read from xcodeproj if omitted)")
    var version: String?

    @Option(name: .long, help: "Locale (e.g. en-US, ja)")
    var locale: String

    @Option(name: .long, help: "Display type (e.g. IPHONE_67, IPHONE_65, IPAD_PRO_3GEN_129)")
    var displayType: String

    @Option(name: .long, help: "Path to video file (.mp4 / .mov)")
    var video: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id or ios.bundleId required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: video) else {
            Logger.error("Video file not found: \(video)"); Foundation.exit(1)
        }

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let ver = try resolveVersion(version: version, cfg: cfg)
        let appID = try await client.findApp(bundleID: bid)
        let versionID = try await client.getAppStoreVersion(appID: appID, version: ver)
        let localizations = try await client.getLocalizations(versionID: versionID)

        guard let loc = localizations.first(where: {
            ($0["attributes"] as? [String: Any])?["locale"] as? String == locale
        }), let locID = loc["id"] as? String else {
            Logger.error("Locale '\(locale)' not found for this version"); Foundation.exit(1)
        }

        let sets = try await client.getPreviewSets(localizationID: locID)
        let previewType = "APP_\(displayType)"
        guard let set = sets.first(where: {
            ($0["attributes"] as? [String: Any])?["previewType"] as? String == previewType
        }), let setID = set["id"] as? String else {
            Logger.error("No preview set for type \(previewType)"); Foundation.exit(1)
        }

        let videoData = try Data(contentsOf: URL(fileURLWithPath: video))
        let md5 = Insecure.MD5.hash(data: videoData).map { String(format: "%02x", $0) }.joined()
        let fileName = URL(fileURLWithPath: video).lastPathComponent

        Logger.step("Uploading \(fileName) (\(videoData.count / 1024 / 1024) MB)")
        let (previewID, uploadURL) = try await client.reservePreview(setID: setID, fileName: fileName, fileSize: videoData.count)

        var uploadReq = URLRequest(url: URL(string: uploadURL)!)
        uploadReq.httpMethod = "PUT"
        uploadReq.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        uploadReq.httpBody = videoData
        _ = try await URLSession.shared.data(for: uploadReq)

        Logger.info("Committing upload...")
        try await client.commitPreview(id: previewID, md5: md5, fileSize: videoData.count)
        Logger.success("Preview video uploaded: \(fileName)")
    }
}

// MARK: - delete

struct IOSPreviewsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a preview video by ID"
    )

    @Option(name: .long, help: "Preview video ID")
    var previewID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting preview \(previewID)")
        try await client.deletePreview(id: previewID)
        Logger.success("Deleted")
    }
}

// MARK: - Helpers

private func resolveVersion(version: String?, cfg: Config.iOS?) throws -> String {
    if let version { return version }
    if let proj = cfg?.project, let tgt = cfg?.scheme {
        return try XcodeProject.versionNumber(project: proj, target: tgt)
    }
    Logger.error("--version or ios.project + ios.scheme in .launchpadrc required")
    Foundation.exit(1)
}
