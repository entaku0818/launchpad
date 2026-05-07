import ArgumentParser
import CryptoKit
import Foundation

struct IOSAppScreenshotsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-screenshots",
        abstract: "Manage individual screenshots within a screenshot set",
        subcommands: [
            IOSAppScreenshotsListCommand.self,
            IOSAppScreenshotsUploadCommand.self,
            IOSAppScreenshotsOrderCommand.self,
            IOSAppScreenshotsDeleteCommand.self,
        ]
    )
}

struct IOSAppScreenshotsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List screenshots in a set")

    @Option(name: .long, help: "Screenshot set ID (from ios screenshot-sets list)")
    var setID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching screenshots for set \(setID)")
        let shots = try await client.getScreenshots(setID: setID)

        if shots.isEmpty { Logger.info("No screenshots found"); return }
        Logger.info("\(shots.count) screenshot(s)\n")
        for s in shots {
            guard let id = s["id"] as? String,
                  let attrs = s["attributes"] as? [String: Any] else { continue }
            let name  = attrs["fileName"] as? String ?? "-"
            let state = (attrs["assetDeliveryState"] as? [String: Any])?["state"] as? String ?? "-"
            let order = attrs["displayOrder"] as? Int ?? 0
            print("  [\(order)] \(name)  [\(state)]  id: \(id)")
        }
    }
}

struct IOSAppScreenshotsUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload a screenshot to a set")

    @Option(name: .long, help: "Screenshot set ID (from ios screenshot-sets list)")
    var setID: String

    @Option(name: .long, help: "Path to PNG image file")
    var image: String

    mutating func run() async throws {
        DotEnv.load()
        guard FileManager.default.fileExists(atPath: image) else {
            Logger.error("Image file not found: \(image)"); Foundation.exit(1)
        }
        let imageData = try Data(contentsOf: URL(fileURLWithPath: image))
        let md5 = Insecure.MD5.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let fileName = URL(fileURLWithPath: image).lastPathComponent

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Uploading \(fileName) to set \(setID)")
        let (screenshotID, uploadURL) = try await client.reserveScreenshot(setID: setID, fileName: fileName, fileSize: imageData.count)

        var uploadReq = URLRequest(url: URL(string: uploadURL)!)
        uploadReq.httpMethod = "PUT"
        uploadReq.setValue("image/png", forHTTPHeaderField: "Content-Type")
        uploadReq.httpBody = imageData
        _ = try await URLSession.shared.data(for: uploadReq)

        Logger.info("Committing upload...")
        try await client.commitScreenshot(id: screenshotID, md5: md5, fileSize: imageData.count)
        Logger.success("Screenshot uploaded: \(fileName)  id: \(screenshotID)")
    }
}

struct IOSAppScreenshotsOrderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "order", abstract: "Set the display order of a screenshot within its set")

    @Option(name: .long, help: "Screenshot ID (from list)")
    var screenshotID: String

    @Option(name: .long, help: "Display position (0-based)")
    var position: Int

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Setting screenshot \(screenshotID) to position \(position)")
        try await client.reorderScreenshot(id: screenshotID, displayOrder: position)
        Logger.success("Screenshot order updated")
    }
}

struct IOSAppScreenshotsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a screenshot by ID")

    @Option(name: .long, help: "Screenshot ID (from list)")
    var screenshotID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting screenshot \(screenshotID)")
        try await client.deleteScreenshot(id: screenshotID)
        Logger.success("Screenshot deleted")
    }
}
